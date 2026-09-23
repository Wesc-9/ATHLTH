import SwiftUI

struct AdvancedPlannerView: View {
    @EnvironmentObject private var session: AppSessionStore

    let onOpenPrograms: () -> Void

    @State private var showingSessionEditor = false
    @State private var selectedDayID: UUID?

    init(onOpenPrograms: @escaping () -> Void = {}) {
        self.onOpenPrograms = onOpenPrograms
    }

    var body: some View {
        VStack(spacing: 16) {
            if let plan = session.activePlan {
                ATHLTHCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.title)
                                .font(.title2.weight(.bold))
                            Text(
                                "Version \(plan.version) · \(plan.visibility.title) · \(plan.weeks.count) weeks"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            session.addWeekToActivePlan()
                        } label: {
                            Label("Add week", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                ForEach(plan.weeks) { week in
                    ATHLTHCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Week \(week.weekNumber)")
                                    .font(.headline)
                                Text(week.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(
                                "\(week.days.reduce(0) { $0 + $1.sessions.count }) sessions"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 12) {
                            ForEach(week.days) { day in
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack {
                                        Text(day.title)
                                            .font(.subheadline.weight(.semibold))

                                        Spacer()

                                        Button {
                                            selectedDayID = day.id
                                            showingSessionEditor = true
                                        } label: {
                                            Image(systemName: "plus.circle.fill")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(ATHLTHTheme.accent)
                                    }

                                    if day.sessions.isEmpty {
                                        Label(
                                            "Rest / recovery day",
                                            systemImage: "leaf"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(day.sessions) { workout in
                                            sessionRow(workout, dayID: day.id)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(
                                    .ultraThinMaterial,
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No active program",
                    systemImage: "calendar.badge.plus",
                    description: Text(
                        "Choose or create a program first. Calendar is where its sessions are scheduled and adjusted."
                    )
                )

                Button {
                    onOpenPrograms()
                } label: {
                    Label("Open Programs", systemImage: "square.stack.3d.up.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
            }
        }
        .sheet(isPresented: $showingSessionEditor) {
            if let selectedDayID {
                SessionEditorView(dayID: selectedDayID)
            }
        }
    }

    private func sessionRow(
        _ workout: PlannedSession,
        dayID: UUID
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: workout.kind.systemImage)
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title)
                    .font(.subheadline.weight(.medium))

                Text(sessionSummary(workout))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                session.removeSession(workout.id, fromDay: dayID)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }

    private func sessionSummary(_ workout: PlannedSession) -> String {
        var parts: [String] = []

        if let running = workout.runningWorkout {
            parts.append(running.type.title)
            parts.append("\(running.blocks.count) blocks")
        } else {
            if let duration = workout.durationMinutes {
                parts.append("\(duration) min")
            }

            if let distance = workout.targetDistanceKilometers {
                parts.append(String(format: "%.1f km", distance))
            }
        }

        if !workout.exercises.isEmpty {
            parts.append("\(workout.exercises.count) exercises")
        }

        if workout.routeID != nil {
            parts.append("Route")
        }

        return parts.isEmpty
            ? workout.kind.title
            : parts.joined(separator: " · ")
    }
}

struct TrainingPlanManagerView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var goalStore: GoalStore

    let onOpenCalendar: () -> Void

    @State private var showingPlanEditor = false
    @State private var showingProgramCreation = false
    @State private var programToStart: TrainingPlan?

    init(onOpenCalendar: @escaping () -> Void = {}) {
        self.onOpenCalendar = onOpenCalendar
    }

    var body: some View {
        VStack(spacing: 16) {
            ATHLTHCard {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Program Library")
                            .font(.title3.weight(.bold))
                        Text(
                            "Programs are reusable training structures. Start one when you're ready, then manage its actual dates and sessions in Calendar."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showingProgramCreation = true
                    } label: {
                        Label("Create", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(ATHLTHTheme.accent)
                }
            }

            if !session.planTemplates.isEmpty {
                ATHLTHCard {
                    ATHLTHSectionHeader(
                        title: "Saved Programs",
                        actionTitle: "\(session.planTemplates.count)"
                    )

                    VStack(spacing: 10) {
                        ForEach(session.planTemplates) { template in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(
                                        template.tags.isEmpty
                                            ? "\(template.weeks.count) weeks"
                                            : "\(template.weeks.count) weeks · \(template.tags.joined(separator: ", "))"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }

                                Spacer()

                                Button("Start") {
                                    programToStart = template
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(role: .destructive) {
                                    session.deletePlanTemplate(template.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }

            if let plan = session.activePlan {
                ATHLTHCard {
                    HStack {
                        ATHLTHSectionHeader(title: "Active Program")

                        Spacer()

                        Button("Calendar") {
                            onOpenCalendar()
                        }
                        .font(.caption.weight(.semibold))

                        Button("Edit") {
                            showingPlanEditor = true
                        }
                        .font(.caption.weight(.semibold))
                    }

                    VStack(spacing: 12) {
                        LabeledContent("Program", value: plan.title)
                        LabeledContent("Version", value: "\(plan.version)")
                        LabeledContent("Weeks", value: "\(plan.weeks.count)")
                        LabeledContent("Visibility", value: plan.visibility.title)

                        if !plan.tags.isEmpty {
                            LabeledContent(
                                "Tags",
                                value: plan.tags.joined(separator: ", ")
                            )
                        }
                    }
                    .padding(.top, 10)
                }

                ATHLTHCard {
                    HStack {
                        ATHLTHSectionHeader(
                            title: "Linked Goals",
                            actionTitle: "Edit Program"
                        )

                        Spacer()

                        Text(
                            "\(goalStore.goals.filter { $0.linkedTrainingPlanID == plan.id }.count)"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                    }

                    let linked = goalStore.goals.filter {
                        $0.linkedTrainingPlanID == plan.id
                    }

                    if linked.isEmpty {
                        Text("No goals are linked to this program yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(linked) { goal in
                                HStack {
                                    Image(systemName: goal.category.systemImage)
                                        .foregroundStyle(ATHLTHTheme.accent)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(goal.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(
                                            "\(goal.completedMilestones) of \(goal.milestones.count) milestones"
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text("\(Int((goal.progress * 100).rounded()))%")
                                        .font(.caption.bold())
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                }

                ATHLTHCard {
                    ATHLTHSectionHeader(
                        title: "Spotify",
                        actionTitle: "Program only"
                    )

                    if settings.spotifyConnected {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                plan.spotifyPlaylist?.name ?? "No playlist linked",
                                systemImage: "music.note"
                            )
                            .font(.headline)

                            Text(
                                plan.spotifyPlaylist == nil
                                    ? "ATHLTH only shows real playlists linked to this program."
                                    : "This playlist can start automatically with workouts from this program."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if plan.spotifyPlaylist != nil {
                                Toggle(
                                    "Autoplay when workout starts",
                                    isOn: Binding(
                                        get: {
                                            plan.spotifyAutoplayOnWorkoutStart
                                        },
                                        set: {
                                            session.setActivePlanSpotifyAutoplay($0)
                                        }
                                    )
                                )
                            }

                            NavigationLink {
                                SpotifySettingsView()
                            } label: {
                                Label(
                                    "Spotify Settings",
                                    systemImage: "gearshape"
                                )
                            }
                        }
                        .padding(.top, 10)
                    } else {
                        NavigationLink {
                            SpotifySettingsView()
                        } label: {
                            Label(
                                "Connect Spotify",
                                systemImage: "music.note"
                            )
                        }
                        .padding(.top, 8)
                    }
                }

                ATHLTHCard {
                    ATHLTHSectionHeader(title: "Program building blocks")

                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "Multiple sessions per day",
                            systemImage: "square.stack.3d.up.fill"
                        )
                        Label(
                            "Strength, run, walk, mobility and recovery",
                            systemImage: "figure.mixed.cardio"
                        )
                        Label(
                            "Structured run blocks, routes and intensity",
                            systemImage: "figure.run"
                        )
                        Label(
                            "Sets, reps, load, RPE, RIR and rest",
                            systemImage: "dumbbell.fill"
                        )
                        Label(
                            "Supersets and progression rules",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Label(
                            "Private, friends or public programs",
                            systemImage: "person.2.fill"
                        )
                    }
                    .font(.subheadline)
                    .padding(.top, 10)
                }

                HStack(spacing: 10) {
                    Button {
                        session.saveActivePlanAsTemplate()
                    } label: {
                        Label(
                            "Save to Library",
                            systemImage: "square.and.arrow.down"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)

                    Button {
                        session.duplicateActivePlan()
                    } label: {
                        Label(
                            "Duplicate Program",
                            systemImage: "doc.on.doc"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView(
                    "No active program",
                    systemImage: "square.stack.3d.up",
                    description: Text(
                        session.planTemplates.isEmpty
                            ? "Create your first program here. Once started, its sessions appear in Calendar."
                            : "Start a saved program from your library, or create a new one."
                    )
                )

                if session.planTemplates.isEmpty {
                    Button {
                        showingProgramCreation = true
                    } label: {
                        Label("Create Program", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showingPlanEditor) {
            if let plan = session.activePlan {
                PlanMetadataEditorView(plan: plan)
            }
        }
        .sheet(isPresented: $showingProgramCreation) {
            TrainingPlanCreationView()
        }
        .sheet(item: $programToStart) { program in
            ProgramStartView(
                program: program,
                onStarted: onOpenCalendar
            )
        }
    }
}

private struct ProgramStartView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let program: TrainingPlan
    let onStarted: () -> Void

    @State private var startDate = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    Text(program.title)
                        .font(.headline)

                    if !program.summary.isEmpty {
                        Text(program.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Length", value: "\(program.weeks.count) weeks")
                }

                Section("Add to Calendar") {
                    DatePicker(
                        "Start date",
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    Text(
                        "Starting the program makes it your active program and places its weeks into Calendar from this date."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Start Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        session.usePlanTemplate(
                            program.id,
                            startDate: startDate
                        )
                        dismiss()
                        onStarted()
                    }
                }
            }
        }
    }
}

private enum ProgramTimelineMode: String, CaseIterable, Identifiable {
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

struct TrainingPlanCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    @State private var title = "My Program"
    @State private var summary = ""
    @State private var timelineMode: ProgramTimelineMode = .weeks
    @State private var weekCount = 4
    @State private var customWeeks = 12
    @State private var useCustomWeeks = false
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var endDate = Calendar.current.date(
        byAdding: .day,
        value: 27,
        to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()
    @State private var visibility: ProfileVisibility = .privateOnly
    @State private var selectedGoalIDs: Set<UUID> = []

    private let quickDurations = [1, 3, 4, 8, 12, 16, 24]

    private var resolvedWeeks: Int {
        switch timelineMode {
        case .weeks:
            return useCustomWeeks ? customWeeks : weekCount
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
        let calendar = Calendar.current
        switch timelineMode {
        case .weeks:
            return calendar.date(
                byAdding: .day,
                value: max(resolvedWeeks * 7 - 1, 0),
                to: calendar.startOfDay(for: startDate)
            ) ?? startDate
        case .endDate:
            return calendar.startOfDay(for: endDate)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    TextField("Program name", text: $title)
                    TextField(
                        "What are you training for?",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    Picker("Visibility", selection: $visibility) {
                        ForEach(ProfileVisibility.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                Section("Timeline") {
                    DatePicker(
                        "Start date",
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    Picker("Plan by", selection: $timelineMode) {
                        ForEach(ProgramTimelineMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if timelineMode == .weeks {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 78), spacing: 8)
                            ],
                            spacing: 8
                        ) {
                            ForEach(quickDurations, id: \.self) { weeks in
                                Button {
                                    weekCount = weeks
                                    useCustomWeeks = false
                                } label: {
                                    VStack(spacing: 3) {
                                        Text("\(weeks)")
                                            .font(.headline)
                                        Text(weeks == 1 ? "week" : "weeks")
                                            .font(.caption2)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .foregroundStyle(
                                        !useCustomWeeks && weekCount == weeks
                                            ? .white
                                            : .primary
                                    )
                                    .background(
                                        !useCustomWeeks && weekCount == weeks
                                            ? ATHLTHTheme.accent
                                            : Color(.tertiarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Toggle(
                            "Custom program length",
                            isOn: $useCustomWeeks
                        )

                        if useCustomWeeks {
                            Stepper(
                                "\(customWeeks) weeks",
                                value: $customWeeks,
                                in: 1...52
                            )
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
                .onChange(of: startDate) { _, newStart in
                    if endDate < newStart {
                        endDate = Calendar.current.date(
                            byAdding: .day,
                            value: 6,
                            to: newStart
                        ) ?? newStart
                    }
                }

                if !goalStore.goals.isEmpty {
                    Section("Connect Goals") {
                        ForEach(goalStore.goals) { goal in
                            Toggle(
                                isOn: Binding(
                                    get: { selectedGoalIDs.contains(goal.id) },
                                    set: { enabled in
                                        if enabled {
                                            selectedGoalIDs.insert(goal.id)
                                        } else {
                                            selectedGoalIDs.remove(goal.id)
                                        }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.title)
                                    Text(goal.category.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("Every week starts empty. Add exactly the strength, running, walking, mobility or recovery sessions you want to each day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        session.createTrainingPlan(
                            title: title,
                            summary: summary,
                            weekCount: resolvedWeeks,
                            startDate: startDate,
                            visibility: visibility
                        )

                        if let planID = session.activePlan?.id {
                            goalStore.setLinkedPlan(
                                planID,
                                goalIDs: selectedGoalIDs
                            )
                        }

                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}

struct PlanMetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    let plan: TrainingPlan

    @State private var title: String
    @State private var summary: String
    @State private var visibility: ProfileVisibility
    @State private var tags: String
    @State private var startDateEnabled: Bool
    @State private var startDate: Date
    @State private var selectedGoalIDs: Set<UUID> = []

    init(plan: TrainingPlan) {
        self.plan = plan
        _title = State(initialValue: plan.title)
        _summary = State(initialValue: plan.summary)
        _visibility = State(initialValue: plan.visibility)
        _tags = State(initialValue: plan.tags.joined(separator: ", "))
        _startDateEnabled = State(initialValue: plan.startDate != nil)
        _startDate = State(initialValue: plan.startDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Title", text: $title)
                    TextField(
                        "Summary",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    Picker("Visibility", selection: $visibility) {
                        ForEach(ProfileVisibility.allCases) { visibility in
                            Text(visibility.title).tag(visibility)
                        }
                    }

                    Toggle("Use calendar start date", isOn: $startDateEnabled)

                    if startDateEnabled {
                        DatePicker(
                            "Program starts",
                            selection: $startDate,
                            displayedComponents: .date
                        )
                    }

                    TextField(
                        "Tags, comma separated",
                        text: $tags
                    )
                    .textInputAutocapitalization(.never)
                }

                Section("Goals") {
                    if goalStore.goals.isEmpty {
                        Text("Create a Goal in Progress to connect it to this program.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(goalStore.goals) { goal in
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
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.title)
                                    Text(goal.category.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Text(
                        "Changing a program creates a new local version. Shared-program sync can use this version number later."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Program")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selectedGoalIDs = Set(
                    goalStore.goals
                        .filter { $0.linkedTrainingPlanID == plan.id }
                        .map(\.id)
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.updateActivePlanMetadata(
                            title: title,
                            summary: summary,
                            visibility: visibility,
                            tags: tags
                                .split(separator: ",")
                                .map(String.init),
                            startDate: startDateEnabled
                                ? Calendar.current.startOfDay(for: startDate)
                                : nil
                        )
                        goalStore.setLinkedPlan(
                            plan.id,
                            goalIDs: selectedGoalIDs
                        )
                        dismiss()
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}

struct SessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore

    let dayID: UUID

    @State private var title = "New Workout"
    @State private var kind: WorkoutKind = .strength
    @State private var durationMinutes = 45
    @State private var distanceKilometers = 5.0
    @State private var notes = ""

    @State private var plannedExercises: [PlannedExercise] = []
    @State private var exerciseBeingEdited: PlannedExercise?
    @State private var showingExerciseLibrary = false

    @State private var selectedRunningWorkout: RunningWorkoutTemplate?
    @State private var showingRunningLibrary = false
    @State private var selectedRouteID: UUID?

    @State private var scheduledTimeEnabled = false
    @State private var scheduledTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Title", text: $title)

                    Picker("Type", selection: $kind) {
                        ForEach(WorkoutKind.allCases) { kind in
                            Label(
                                kind.title,
                                systemImage: kind.systemImage
                            )
                            .tag(kind)
                        }
                    }

                    Toggle(
                        "Set a time",
                        isOn: $scheduledTimeEnabled
                    )

                    if scheduledTimeEnabled {
                        DatePicker(
                            "Start",
                            selection: $scheduledTime,
                            displayedComponents: .hourAndMinute
                        )
                    }

                    if kind != .running {
                        Stepper(
                            "Duration: \(durationMinutes) min",
                            value: $durationMinutes,
                            in: 5...300,
                            step: 5
                        )
                    }

                    if kind == .walking {
                        Stepper(
                            "Distance: \(distanceKilometers, specifier: "%.1f") km",
                            value: $distanceKilometers,
                            in: 0.5...100,
                            step: 0.5
                        )
                    }

                    TextField(
                        "Notes",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                }

                if kind == .strength {
                    strengthBuilder
                }

                if kind == .running {
                    runningBuilder
                }

                if kind == .walking {
                    routeBuilder
                }

                if kind == .recovery || kind == .mobility {
                    Section("Recovery / Mobility") {
                        Text(
                            "Use duration and notes to describe the session. Structured mobility blocks can be added to the same planner model later."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSession()
                    }
                    .disabled(!canAdd)
                }
            }
            .sheet(isPresented: $showingExerciseLibrary) {
                NavigationStack {
                    ExerciseLibraryView(
                        selectionTitle: "Add to Workout"
                    ) { entry in
                        addExercise(entry.exercise)
                        showingExerciseLibrary = false
                    }
                }
            }
            .sheet(item: $exerciseBeingEdited) { exercise in
                PlannedExerciseEditorView(
                    exercise: exercise
                ) { updated in
                    if let index = plannedExercises.firstIndex(
                        where: { $0.id == updated.id }
                    ) {
                        plannedExercises[index] = updated
                    }
                    exerciseBeingEdited = nil
                }
            }
            .sheet(isPresented: $showingRunningLibrary) {
                NavigationStack {
                    RunningWorkoutLibraryView(
                        selectionTitle: "Use in Plan"
                    ) { workout in
                        selectedRunningWorkout = workout
                        title = workout.title
                        showingRunningLibrary = false
                    }
                }
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .strength && title == "New Workout" {
                    title = "Strength Workout"
                } else if newKind == .running && title == "New Workout" {
                    title = "Running Workout"
                } else if newKind == .walking && title == "New Workout" {
                    title = "Walk"
                }
            }
        }
    }

    private var strengthBuilder: some View {
        Section("Strength Exercises") {
            if plannedExercises.isEmpty {
                Text(
                    "Add exercises from RepDB or your own custom library."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(Array(plannedExercises.enumerated()), id: \.element.id) { index, planned in
                    Button {
                        exerciseBeingEdited = planned
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 26, height: 26)
                                .background(
                                    ATHLTHTheme.accent.opacity(0.10),
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(planned.embeddedExercise.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(plannedExerciseSummary(planned))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if planned.supersetGroupID != nil {
                                Text("SUPERSET")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.orange)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            plannedExercises.removeAll {
                                $0.id == planned.id
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    if index > 0 {
                        Button {
                            toggleSuperset(at: index)
                        } label: {
                            Label(
                                planned.supersetGroupID == nil
                                    ? "Superset with previous"
                                    : "Remove superset",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.caption)
                        }
                    }
                }
                .onMove { offsets, destination in
                    plannedExercises.move(
                        fromOffsets: offsets,
                        toOffset: destination
                    )
                }
            }

            Button {
                showingExerciseLibrary = true
            } label: {
                Label(
                    "Add Exercise",
                    systemImage: "plus.circle.fill"
                )
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private var runningBuilder: some View {
        Group {
            Section("Running Workout") {
                if let workout = selectedRunningWorkout {
                    Button {
                        showingRunningLibrary = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: workout.type.systemImage)
                                    .foregroundStyle(ATHLTHTheme.accent)
                                Text(workout.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }

                            Text(workout.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(
                                "\(workout.blocks.count) blocks · \(workout.type.title)"
                            )
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(
                        Array(workout.blocks.enumerated()),
                        id: \.element.id
                    ) { index, block in
                        RunningWorkoutBlockRow(
                            index: index + 1,
                            block: block
                        )
                    }
                } else {
                    Button {
                        showingRunningLibrary = true
                    } label: {
                        Label(
                            "Choose or Build Running Workout",
                            systemImage: "figure.run.circle.fill"
                        )
                    }

                    Text(
                        "Choose Easy, Long Run, Tempo, Threshold, Intervals, Fartlek, Hills, Race Pace, Progression or a custom workout."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            routeBuilder
        }
    }

    private var routeBuilder: some View {
        Section("Route") {
            Picker("Route", selection: $selectedRouteID) {
                Text("No specific route")
                    .tag(nil as UUID?)

                ForEach(session.savedRoutes) { route in
                    Text(
                        "\(route.title) · \(route.distanceKilometers, specifier: "%.1f") km"
                    )
                    .tag(route.id as UUID?)
                }
            }

            if session.savedRoutes.isEmpty {
                Text(
                    "Import a GPX route from Train if you want this session tied to a specific route."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var canAdd: Bool {
        let cleanTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else { return false }

        if kind == .strength {
            return !plannedExercises.isEmpty
        }

        if kind == .running {
            return selectedRunningWorkout != nil
        }

        return true
    }

    private func addExercise(_ exercise: Exercise) {
        let planned = PlannedExercise(
            id: UUID(),
            exerciseID: exercise.id,
            embeddedExercise: exercise.snapshot,
            sets: 3,
            reps: 8,
            targetWeightKilograms: nil,
            targetRPE: nil,
            restSeconds: 90,
            notes: nil,
            targetRIR: nil,
            supersetGroupID: nil,
            progression: StrengthProgressionRule.none
        )

        plannedExercises.append(planned)
    }

    private func toggleSuperset(at index: Int) {
        guard index > 0,
              plannedExercises.indices.contains(index),
              plannedExercises.indices.contains(index - 1)
        else {
            return
        }

        if plannedExercises[index].supersetGroupID != nil {
            let group = plannedExercises[index].supersetGroupID
            plannedExercises[index].supersetGroupID = nil

            if plannedExercises[index - 1].supersetGroupID == group {
                plannedExercises[index - 1].supersetGroupID = nil
            }
        } else {
            let group =
                plannedExercises[index - 1].supersetGroupID ??
                UUID()

            plannedExercises[index - 1].supersetGroupID = group
            plannedExercises[index].supersetGroupID = group
        }
    }

    private func addSession() {
        let cleanNotes = notes
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let workout = PlannedSession(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            scheduledStart: scheduledTimeEnabled
                ? scheduledTime
                : nil,
            durationMinutes: kind == .running
                ? nil
                : durationMinutes,
            targetDistanceKilometers: kind == .walking
                ? distanceKilometers
                : selectedRunningWorkout?
                    .estimatedDistanceMeters
                    .map { $0 / 1_000 },
            targetPaceSecondsPerKilometer: nil,
            routeID: selectedRouteID,
            exercises: kind == .strength
                ? plannedExercises
                : [],
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            runningWorkout: kind == .running
                ? selectedRunningWorkout
                : nil
        )

        session.addSession(workout, toDay: dayID)
        dismiss()
    }

    private func plannedExerciseSummary(
        _ planned: PlannedExercise
    ) -> String {
        var parts = [
            "\(planned.sets) × \(planned.reps ?? 0)"
        ]

        if let weight = planned.targetWeightKilograms {
            parts.append(String(format: "%.1f kg", weight))
        }

        if let rpe = planned.targetRPE {
            parts.append(String(format: "RPE %.1f", rpe))
        }

        if let rir = planned.targetRIR {
            parts.append(String(format: "RIR %.1f", rir))
        }

        if let rest = planned.restSeconds {
            parts.append("\(rest)s rest")
        }

        if let progression = planned.progression,
           progression.kind != .none {
            parts.append(progression.kind.title)
        }

        return parts.joined(separator: " · ")
    }
}

struct PlannedExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let original: PlannedExercise
    let onSave: (PlannedExercise) -> Void

    @State private var sets: Int
    @State private var reps: Int
    @State private var weight: Double
    @State private var useWeight: Bool

    @State private var useRPE: Bool
    @State private var rpe: Double

    @State private var useRIR: Bool
    @State private var rir: Double

    @State private var restSeconds: Int
    @State private var progressionKind: StrengthProgressionKind
    @State private var progressionAmount: Double
    @State private var minimumReps: Int
    @State private var maximumReps: Int
    @State private var notes: String

    init(
        exercise: PlannedExercise,
        onSave: @escaping (PlannedExercise) -> Void
    ) {
        original = exercise
        self.onSave = onSave

        _sets = State(initialValue: exercise.sets)
        _reps = State(initialValue: exercise.reps ?? 8)
        _weight = State(
            initialValue: exercise.targetWeightKilograms ?? 20
        )
        _useWeight = State(
            initialValue: exercise.targetWeightKilograms != nil
        )

        _useRPE = State(
            initialValue: exercise.targetRPE != nil
        )
        _rpe = State(initialValue: exercise.targetRPE ?? 8)

        _useRIR = State(
            initialValue: exercise.targetRIR != nil
        )
        _rir = State(initialValue: exercise.targetRIR ?? 2)

        _restSeconds = State(
            initialValue: exercise.restSeconds ?? 90
        )

        _progressionKind = State(
            initialValue: exercise.progression?.kind ?? .none
        )
        _progressionAmount = State(
            initialValue: exercise.progression?.amount ?? 2.5
        )
        _minimumReps = State(
            initialValue: exercise.progression?.minimumReps ?? 8
        )
        _maximumReps = State(
            initialValue: exercise.progression?.maximumReps ?? 12
        )
        _notes = State(initialValue: exercise.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(original.embeddedExercise.name) {
                    Stepper(
                        "Sets: \(sets)",
                        value: $sets,
                        in: 1...20
                    )

                    Stepper(
                        "Reps: \(reps)",
                        value: $reps,
                        in: 1...100
                    )

                    Toggle(
                        "Target weight",
                        isOn: $useWeight
                    )

                    if useWeight {
                        HStack {
                            Text("Weight")
                            Spacer()
                            TextField(
                                "kg",
                                value: $weight,
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                            Text("kg")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(
                        "Rest: \(restSeconds) sec",
                        value: $restSeconds,
                        in: 0...600,
                        step: 15
                    )
                }

                Section("Effort") {
                    Toggle("Use RPE", isOn: $useRPE)

                    if useRPE {
                        HStack {
                            Slider(
                                value: $rpe,
                                in: 1...10,
                                step: 0.5
                            )
                            Text("\(rpe, specifier: "%.1f")")
                                .monospacedDigit()
                        }
                    }

                    Toggle("Use RIR", isOn: $useRIR)

                    if useRIR {
                        HStack {
                            Slider(
                                value: $rir,
                                in: 0...5,
                                step: 0.5
                            )
                            Text("\(rir, specifier: "%.1f")")
                                .monospacedDigit()
                        }
                    }
                }

                Section("Progression") {
                    Picker(
                        "Rule",
                        selection: $progressionKind
                    ) {
                        ForEach(
                            StrengthProgressionKind.allCases
                        ) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    if progressionKind != .none {
                        HStack {
                            Text(
                                progressionKind == .addReps
                                    ? "Reps to add"
                                    : progressionKind == .percentage
                                        ? "Percent"
                                        : "Weight to add"
                            )

                            Spacer()

                            TextField(
                                "Amount",
                                value: $progressionAmount,
                                format: .number.precision(.fractionLength(0...2))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)

                            Text(
                                progressionKind == .percentage
                                    ? "%"
                                    : progressionKind == .addReps
                                        ? "reps"
                                        : "kg"
                            )
                            .foregroundStyle(.secondary)
                        }

                        if progressionKind == .doubleProgression {
                            Stepper(
                                "Rep range start: \(minimumReps)",
                                value: $minimumReps,
                                in: 1...50
                            )
                            Stepper(
                                "Rep range end: \(maximumReps)",
                                value: $maximumReps,
                                in: minimumReps...100
                            )
                        }

                        Text(
                            "The next prescription can use this rule after all planned sets are completed. ATHLTH keeps the rule separate from the recorded workout history."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField(
                        "Technique or progression notes",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                }
            }
            .navigationTitle("Exercise Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = original
                        updated.sets = sets
                        updated.reps = reps
                        updated.targetWeightKilograms =
                            useWeight ? weight : nil
                        updated.targetRPE =
                            useRPE ? rpe : nil
                        updated.targetRIR =
                            useRIR ? rir : nil
                        updated.restSeconds = restSeconds
                        updated.notes = notes
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .nilIfEmpty
                        updated.progression = StrengthProgressionRule(
                            kind: progressionKind,
                            amount: max(progressionAmount, 0),
                            minimumReps:
                                progressionKind == .doubleProgression
                                    ? minimumReps
                                    : nil,
                            maximumReps:
                                progressionKind == .doubleProgression
                                    ? maximumReps
                                    : nil,
                            applyWhenAllSetsCompleted: true
                        )

                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
