import PhotosUI
import SwiftUI
import UIKit

struct GoalsHubView: View {
    @EnvironmentObject private var goalStore: GoalStore
    @State private var showingCreateGoal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Goals")
                            .font(.largeTitle.bold())
                        Text("Turn the things that matter into measurable progress.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showingCreateGoal = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(ATHLTHTheme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let primary = goalStore.primaryGoal {
                    Text("PRIMARY GOAL")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        GoalDetailView(goalID: primary.id)
                    } label: {
                        GoalSummaryCard(goal: primary, prominent: true)
                    }
                    .buttonStyle(.plain)
                }

                let secondary = goalStore.activeGoals.filter { !$0.isPrimary }
                if !secondary.isEmpty {
                    Text("OTHER GOALS")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)

                    ForEach(secondary) { goal in
                        NavigationLink {
                            GoalDetailView(goalID: goal.id)
                        } label: {
                            GoalSummaryCard(goal: goal, prominent: false)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if goalStore.activeGoals.isEmpty {
                    ContentUnavailableView(
                        "No goals yet",
                        systemImage: "target",
                        description: Text("Create a goal and ATHLTH can track milestones from Apple Health, ATHLTH workouts or manual check-ins.")
                    )

                    Button("Create your first goal") {
                        showingCreateGoal = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreateGoal) {
            GoalCreationView()
        }
    }
}

struct GoalSummaryCard: View {
    @EnvironmentObject private var goalStore: GoalStore

    let goal: ATHLTHGoal
    let prominent: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GoalCoverView(goal: goal)
                .frame(height: prominent ? 220 : 145)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if goal.isPrimary {
                        Label("Primary", systemImage: "star.fill")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.18), in: Capsule())
                    }

                    Spacer()

                    if let deadline = goal.deadline {
                        Text(deadline, style: .relative)
                            .font(.caption2.weight(.semibold))
                    }
                }

                Spacer()

                Text(goal.title)
                    .font(prominent ? .title2.bold() : .headline)
                    .lineLimit(2)

                HStack {
                    Text(ATHLTHLocalization.format(
                            english: "%d/%d milestones",
                            norwegian: "%d/%d milepæler",
                            goal.completedMilestones,
                            goal.milestones.count
                        ))
                        .font(.caption)
                    Spacer()
                    Text("\(Int((goal.progress * 100).rounded()))%")
                        .font(.caption.bold())
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.24))
                        Capsule()
                            .fill(.white)
                            .frame(width: proxy.size.width * goal.progress)
                    }
                }
                .frame(height: 6)
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

struct GoalCoverView: View {
    @EnvironmentObject private var goalStore: GoalStore
    let goal: ATHLTHGoal

    var body: some View {
        Group {
            if let url = goalStore.imageURL(for: goal),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(goal.coverStyle.assetName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.04),
                                Color.black.opacity(0.24)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: goal.category.systemImage)
                            .font(.system(size: 64, weight: .medium))
                            .foregroundStyle(.white.opacity(0.16))
                            .padding(22)
                    }
            }
        }
    }

    private var coverColors: [Color] {
        switch goal.coverStyle {
        case .forest: return [ATHLTHTheme.accent.opacity(0.92), .black.opacity(0.88)]
        case .summit: return [.blue.opacity(0.84), .indigo.opacity(0.88)]
        case .track: return [.orange.opacity(0.90), .red.opacity(0.82)]
        case .strength: return [.gray.opacity(0.92), .black]
        case .calm: return [.mint.opacity(0.72), .blue.opacity(0.72)]
        }
    }
}

struct GoalDetailView: View {
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var session: AppSessionStore

    let goalID: UUID

    @State private var showingDeleteConfirmation = false
    @State private var showingAddMilestone = false
    @State private var showingEditGoal = false

    private var goal: ATHLTHGoal? {
        goalStore.goals.first { $0.id == goalID }
    }

    var body: some View {
        Group {
            if let goal {
                ScrollView {
                    VStack(spacing: 18) {
                        hero(goal)
                        progressCard(goal)
                        milestonesCard(goal)

                        if let why = goal.whyItMatters, !why.isEmpty {
                            infoCard(
                                title: "Why this matters",
                                icon: "heart.fill",
                                text: why
                            )
                        }

                        trackingCard(goal)

                        if let notes = goal.notes, !notes.isEmpty {
                            infoCard(
                                title: "Notes",
                                icon: "note.text",
                                text: notes
                            )
                        }

                        actionsCard(goal)
                    }
                    .padding(.bottom, 30)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit Goal", systemImage: "pencil") {
                                showingEditGoal = true
                            }

                            if !goal.isPrimary && goal.status != .completed {
                                Button("Make Primary", systemImage: "star.fill") {
                                    goalStore.setPrimary(goal.id)
                                }
                            }

                            Button("Add Milestone", systemImage: "plus.circle") {
                                showingAddMilestone = true
                            }

                            Divider()

                            Button("Delete Goal", systemImage: "trash", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .task {
                    await goalStore.refreshAutomaticMilestones(
                        health: health,
                        strength: strength
                    )
                }
                .sheet(isPresented: $showingAddMilestone) {
                    AddManualMilestoneView(goalID: goal.id)
                }
                .sheet(isPresented: $showingEditGoal) {
                    GoalEditView(goalID: goal.id)
                }
                .confirmationDialog(
                    "Delete this goal?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete Goal", role: .destructive) {
                        goalStore.delete(goal.id)
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                ContentUnavailableView("Goal unavailable", systemImage: "target")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(_ goal: ATHLTHGoal) -> some View {
        ZStack(alignment: .bottomLeading) {
            GoalCoverView(goal: goal)
                .frame(height: 300)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if goal.isPrimary {
                        Label("PRIMARY", systemImage: "star.fill")
                            .font(.caption2.bold())
                            .tracking(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.18), in: Capsule())
                    }

                    Text(goal.category.title.uppercased())
                        .font(.caption2.bold())
                        .tracking(1)
                }

                Text(goal.title)
                    .font(.system(size: 32, weight: .bold))
                    .lineLimit(2)

                if let deadline = goal.deadline {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(deadline.formatted(.dateTime.day().month(.wide).year()))
                        Text("·")
                        Text(deadline, style: .relative)
                    }
                    .font(.caption)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 300)
    }

    private func progressCard(_ goal: ATHLTHGoal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Progress")
                    .font(.headline)
                Spacer()
                Text("\(Int((goal.progress * 100).rounded()))%")
                    .font(.title2.bold())
                    .foregroundStyle(ATHLTHTheme.accent)
            }

            ProgressView(value: goal.progress)
                .tint(ATHLTHTheme.accent)

            HStack {
                Label(ATHLTHLocalization.format(
                            english: "%d complete",
                            norwegian: "%d fullført",
                            goal.completedMilestones
                        ), systemImage: "checkmark.circle.fill")
                Spacer()
                Text(ATHLTHLocalization.counted(
                            goal.milestones.count,
                            englishSingular: "milestone",
                            englishPlural: "milestones",
                            norwegianSingular: "milepæl",
                            norwegianPlural: "milepæler"
                        ))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let latestEvidence = goal.milestones
                .compactMap(\.lastEvidenceDescription)
                .last {
                Divider()
                Label(latestEvidence, systemImage: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .goalCard()
        .padding(.horizontal)
    }

    private func milestonesCard(_ goal: ATHLTHGoal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Milestones")
                    .font(.title3.bold())
                Spacer()
                Button {
                    showingAddMilestone = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption.bold())
                }
            }
            .padding(.bottom, 8)

            if goal.milestones.isEmpty {
                Text("No milestones yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }

            ForEach(goal.milestones) { milestone in
                milestoneRow(goal: goal, milestone: milestone)

                if milestone.id != goal.milestones.last?.id {
                    Divider()
                        .opacity(0.45)
                }
            }
        }
        .padding()
        .goalCard()
        .padding(.horizontal)
    }

    private func milestoneRow(goal: ATHLTHGoal, milestone: GoalMilestone) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    goalStore.toggleMilestone(
                        goalID: goal.id,
                        milestoneID: milestone.id
                    )
                } label: {
                    Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(milestone.isCompleted ? ATHLTHTheme.accent : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(milestone.title)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(milestone.isCompleted, color: .secondary)

                    Text(milestone.targetDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let method = milestone.completionMethod {
                        Label(completionText(method), systemImage: completionIcon(method))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.accent)
                    } else if let rule = milestone.automationRule, rule.isEnabled {
                        Label(
                            milestone.manualOverride == .forceIncomplete
                                ? "Automatic tracking paused by manual override"
                                : "Automatic from \(rule.dataSource.title)",
                            systemImage: rule.dataSource.systemImage
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    if let evidence = milestone.lastEvidenceDescription,
                       !milestone.isCompleted {
                        Text(ATHLTHLocalization.format(
                            english: "Latest: %@",
                            norwegian: "Siste: %@",
                            evidence
                        ))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if milestone.manualOverride == .forceIncomplete,
               milestone.automationRule?.isEnabled == true {
                Button("Resume automatic tracking") {
                    goalStore.resumeAutomaticTracking(
                        goalID: goal.id,
                        milestoneID: milestone.id
                    )
                    Task {
                        await goalStore.refreshAutomaticMilestones(
                            health: health,
                            strength: strength
                        )
                    }
                }
                .font(.caption2.bold())
                .foregroundStyle(ATHLTHTheme.accent)
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 8)
    }

    private func trackingCard(_ goal: ATHLTHGoal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracking")
                .font(.headline)

            Label(goal.dataSource.title, systemImage: goal.dataSource.systemImage)
                .font(.subheadline.weight(.semibold))

            Text("Automatic milestones only use qualifying data recorded after the goal or milestone was created. Every milestone can also be checked manually.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let deadline = goal.deadline {
                Divider()
                LabeledContent("Deadline") {
                    Text(deadline.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption)
            }

            if let linkedPlanID = goal.linkedTrainingPlanID {
                Divider()
                LabeledContent("Training plan") {
                    if session.activePlan?.id == linkedPlanID {
                        Text(session.activePlan?.title ?? "Linked plan")
                    } else {
                        Text("Linked plan")
                    }
                }
                .font(.caption)
            }

            LabeledContent("Privacy") {
                Text(goal.privacy.title)
            }
            .font(.caption)
        }
        .padding()
        .goalCard()
        .padding(.horizontal)
    }

    private func infoCard(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .goalCard()
        .padding(.horizontal)
    }

    private func actionsCard(_ goal: ATHLTHGoal) -> some View {
        VStack(spacing: 10) {
            if goal.status == .active {
                Button {
                    goalStore.setStatus(.paused, for: goal.id)
                } label: {
                    Label("Pause Goal", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if goal.status == .paused {
                Button {
                    goalStore.setStatus(.active, for: goal.id)
                } label: {
                    Label("Resume Goal", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
            }

            if goal.status != .completed {
                Button {
                    goalStore.setStatus(.completed, for: goal.id)
                } label: {
                    Label("Mark Goal Complete", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
            }
        }
        .padding(.horizontal)
    }

    private func completionText(_ method: GoalCompletionMethod) -> String {
        switch method {
        case .automaticAppleHealth: return "Completed from Apple Health"
        case .automaticATHLTH: return "Completed from ATHLTH"
        case .manual: return "Completed manually"
        }
    }

    private func completionIcon(_ method: GoalCompletionMethod) -> String {
        switch method {
        case .automaticAppleHealth: return "heart.fill"
        case .automaticATHLTH: return "a.circle.fill"
        case .manual: return "hand.tap.fill"
        }
    }
}

struct AddManualMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: GoalStore

    let goalID: UUID

    @State private var title = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Milestone") {
                    TextField("Title", text: $title)
                    TextField("What counts as complete?", text: $detail, axis: .vertical)
                }

                Section {
                    Text("This milestone is manual. You can check or uncheck it at any time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let goal = goalStore.goals.first(where: { $0.id == goalID }) else {
                            return
                        }
                        var milestones = goal.milestones
                        milestones.append(
                            GoalMilestone(
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                targetDescription: detail.isEmpty ? "Manual milestone" : detail
                            )
                        )
                        goalStore.replaceMilestones(milestones, for: goalID)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct GoalCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var session: AppSessionStore

    @State private var step = 0
    @State private var category: GoalCategory = .endurance
    @State private var title = ""
    @State private var targetValue = 5.0
    @State private var exerciseName = "Squat"
    @State private var showingExercisePicker = false
    @State private var activity: GoalActivityFilter = .running
    @State private var hasDeadline = true
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var coverStyle: GoalCoverStyle = .forest
    @State private var whyItMatters = ""
    @State private var notes = ""
    @State private var privacy: GoalPrivacy = .privateOnly
    @State private var makePrimary = true
    @State private var linkActivePlan = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var automaticTracking = true
    @State private var setupMilestones: [GoalMilestone] = []
    @State private var newMilestoneTitle = ""
    @State private var newMilestoneDetail = ""

    private var goalFlowBlue: Color {
        Color(
            red: 0.16,
            green: 0.55,
            blue: 0.98
        )
    }

    private var goalFlowBlueSoft: Color {
        Color(
            red: 0.92,
            green: 0.965,
            blue: 1.0
        )
    }

    private var goalFlowCanvas: Color {
        Color(
            red: 0.965,
            green: 0.970,
            blue: 0.985
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    goalTypeScreen
                } else {
                    goalStepScreen
                }
            }
            .background(
                ATHLTHTheme.canvasTop
                    .ignoresSafeArea()
            )
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .onChange(of: category) { _, newValue in
                applyDefaults(for: newValue)
                automaticTracking = newValue != .custom
                setupMilestones.removeAll()
                newMilestoneTitle = ""
                newMilestoneDetail = ""
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    imageData = try? await item?.loadTransferable(type: Data.self)
                }
            }
        }
        .sheet(
            isPresented: $showingExercisePicker
        ) {
            GoalExercisePickerSheet(
                currentName: exerciseName
            ) { selectedName in
                exerciseName =
                    selectedName
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                showingExercisePicker = false
            }
        }
    }

    private var goalTypeScreen: some View {
        ZStack(alignment: .top) {
            goalStaticHeroBackdrop(height: 344)

            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        goalTypeHero

                        VStack(spacing: 0) {
                            categoryStep
                                .padding(.horizontal, 16)
                                .padding(.top, 22)
                                .padding(.bottom, 122)
                        }
                        .frame(maxWidth: .infinity)
                        .background(
                            goalFlowCanvas,
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 30,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 30,
                                style: .continuous
                            )
                        )
                        .offset(y: -28)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
                .clipped()

                footer
            }
        }
        .background(goalFlowCanvas)
        .clipped()
        .ignoresSafeArea(edges: .top)
    }

    private var goalStepScreen: some View {
        ZStack(alignment: .top) {
            goalStaticHeroBackdrop(height: 286)

            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        goalStepHero

                        VStack(spacing: 14) {
                            goalSelectedCategoryCard

                            Group {
                                switch step {
                                case 1:
                                    targetStep
                                case 2:
                                    identityStep
                                case 3:
                                    milestoneStep
                                default:
                                    reviewStep
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                        .padding(.bottom, 112)
                        .frame(maxWidth: .infinity)
                        .background(
                            goalFlowCanvas,
                            in: UnevenRoundedRectangle(
                                topLeadingRadius: 28,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 28,
                                style: .continuous
                            )
                        )
                        .offset(y: -18)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .background(Color.clear)
                .clipped()

                footer
            }
        }
        .background(goalFlowCanvas)
        .clipped()
        .ignoresSafeArea(edges: .top)
    }

    private func goalStaticHeroBackdrop(
        height: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                Image("OnboardingHero")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: height
                    )
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(
                            color: Color.black.opacity(0.10),
                            location: 0
                        ),
                        .init(
                            color: Color.black.opacity(0.02),
                            location: 0.48
                        ),
                        .init(
                            color: Color.black.opacity(0.18),
                            location: 1
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(
                width: proxy.size.width,
                height: height
            )
            .clipped()
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var goalStepHero: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(
                            color: Color.black.opacity(0.30),
                            location: 0
                        ),
                        .init(
                            color: Color.black.opacity(0.15),
                            location: 0.38
                        ),
                        .init(
                            color: Color.black.opacity(0.76),
                            location: 1
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    HStack(spacing: 11) {
                        Button {
                            withAnimation(
                                .snappy(duration: 0.22)
                            ) {
                                step = max(
                                    0,
                                    step - 1
                                )
                            }
                        } label: {
                            Image(
                                systemName:
                                    "chevron.left"
                            )
                            .font(
                                .system(
                                    size: 15,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(.white)
                            .frame(
                                width: 40,
                                height: 40
                            )
                            .background(
                                .ultraThinMaterial,
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.24),
                                        lineWidth: 0.8
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            ATHLTHLocalization.format(
                                english: "Back",
                                norwegian: "Tilbake"
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text("ATHLTH")
                                .font(
                                    .system(
                                        size: 15,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .tracking(4.0)

                            Text(
                                "MOVE BETTER  LIVE LONGER"
                            )
                            .font(
                                .system(
                                    size: 8.2,
                                    weight: .semibold
                                )
                            )
                            .tracking(2.0)
                            .opacity(0.78)
                        }
                        .foregroundStyle(.white)

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Text(
                                ATHLTHLocalization.format(
                                    english: "Cancel",
                                    norwegian: "Avbryt"
                                )
                            )
                            .font(
                                .system(
                                    size: 11.5,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(
                                .ultraThinMaterial,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        Color.white.opacity(0.20),
                                        lineWidth: 0.7
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 18)

                    HStack {
                        Text(
                            ATHLTHLocalization.format(
                                english: "Step %d of 5",
                                norwegian: "Steg %d av 5",
                                step + 1
                            )
                        )

                        Spacer()

                        Text(stepTitle)
                    }
                    .font(
                        .system(
                            size: 11.5,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.90)
                    )

                    GeometryReader { barProxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(
                                    Color.white.opacity(0.28)
                                )

                            Capsule()
                                .fill(goalFlowBlue)
                                .frame(
                                    width:
                                        barProxy.size.width
                                        * CGFloat(step + 1)
                                        / 5
                                )
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 7)
                    .padding(.bottom, 15)

                    Text(goalStepHeroTitle)
                        .font(
                            .system(
                                size: 27,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(goalStepHeroSubtitle)
                        .font(
                            .system(
                                size: 13,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(
                            .white.opacity(0.88)
                        )
                        .lineLimit(2)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                        .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 50)
                .padding(.bottom, 31)
                .shadow(
                    color: Color.black.opacity(0.22),
                    radius: 10,
                    y: 3
                )
            }
            .frame(
                width: proxy.size.width,
                height: 286
            )
            .clipped()
        }
        .frame(height: 286)
        .clipped()
    }

    private var goalSelectedCategoryCard:
        some View {
        let tint =
            goalCategoryTint(category)

        return HStack(spacing: 12) {
            Image(
                systemName:
                    category.systemImage
            )
            .font(
                .system(
                    size: 16,
                    weight: .semibold
                )
            )
            .foregroundStyle(.white)
            .frame(
                width: 42,
                height: 42
            )
            .background(
                tint,
                in: RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    ATHLTHLocalization.format(
                        english: "Goal type",
                        norwegian: "Måltype"
                    )
                )
                .font(
                    .system(
                        size: 9.5,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .textCase(.uppercase)
                .tracking(0.6)

                Text(category.title)
                    .font(
                        .system(
                            size: 14,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
            }

            Spacer()

            Image(
                systemName:
                    "checkmark.circle.fill"
            )
            .font(.system(size: 18))
            .foregroundStyle(tint)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            Color.white.opacity(0.96),
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
                Color.black.opacity(0.05),
                lineWidth: 0.7
            )
        }
        .shadow(
            color: Color.black.opacity(0.035),
            radius: 8,
            y: 3
        )
    }

    private var goalStepHeroTitle: String {
        switch step {
        case 1:
            return ATHLTHLocalization.format(
                english: "Set the target",
                norwegian: "Sett målet"
            )
        case 2:
            return ATHLTHLocalization.format(
                english: "Make it yours",
                norwegian: "Gjør målet til ditt"
            )
        case 3:
            return ATHLTHLocalization.format(
                english: "Milestones",
                norwegian: "Delmål"
            )
        default:
            return ATHLTHLocalization.format(
                english: "Ready to start",
                norwegian: "Klar til å starte"
            )
        }
    }

    private var goalStepHeroSubtitle:
        String {
        switch step {
        case 1:
            return ATHLTHLocalization.format(
                english:
                    "Choose a clear target. ATHLTH will use it for progress and milestones.",
                norwegian:
                    "Velg et tydelig mål. ATHLTH bruker det til fremdrift og delmål."
            )
        case 2:
            return ATHLTHLocalization.format(
                english:
                    "Add the details that make this goal personal.",
                norwegian:
                    "Legg til detaljene som gjør målet personlig."
            )
        case 3:
            return ATHLTHLocalization.format(
                english:
                    "See the path from today to your final target.",
                norwegian:
                    "Se veien fra i dag til det endelige målet."
            )
        default:
            return ATHLTHLocalization.format(
                english:
                    "Check the essentials before tracking begins.",
                norwegian:
                    "Se over det viktigste før sporingen starter."
            )
        }
    }

    private var goalTypeHero: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(
                            color: Color.black.opacity(0.28),
                            location: 0
                        ),
                        .init(
                            color: Color.black.opacity(0.12),
                            location: 0.40
                        ),
                        .init(
                            color: Color.black.opacity(0.76),
                            location: 1
                        )
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(
                    alignment: .leading,
                    spacing: 0
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("ATHLTH")
                            .font(
                                .system(
                                    size: 24,
                                    weight: .medium,
                                    design: .default
                                )
                            )
                            .tracking(7.2)

                        Text(
                            "MOVE BETTER  LIVE LONGER"
                        )
                        .font(
                            .system(
                                size: 8.5,
                                weight: .semibold
                            )
                        )
                        .tracking(2.25)
                        .opacity(0.82)
                    }
                    .foregroundStyle(.white)

                    Spacer(minLength: 22)

                    HStack {
                        Text(
                            ATHLTHLocalization.format(
                                english: "Step 1 of 5",
                                norwegian: "Steg 1 av 5"
                            )
                        )

                        Spacer()

                        Text(
                            ATHLTHLocalization.format(
                                english: "Goal type",
                                norwegian: "Måltype"
                            )
                        )
                    }
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.92)
                    )

                    GeometryReader { barProxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(
                                    Color.white.opacity(0.30)
                                )

                            Capsule()
                                .fill(goalFlowBlue)
                                .frame(
                                    width:
                                        barProxy.size.width
                                        * 0.20
                                )
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 9)
                    .padding(.bottom, 22)

                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "What do you want to achieve?",
                            norwegian:
                                "Hva vil du oppnå?"
                        )
                    )
                    .font(
                        .system(
                            size: 34,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)

                    Text(
                        ATHLTHLocalization.format(
                            english:
                                "Choose the goal type that fits best. You can adjust the target in the next step.",
                            norwegian:
                                "Velg måltypen som passer best. Du kan justere målet i neste steg."
                        )
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.90)
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.top, 52)
                .padding(.bottom, 42)
                .shadow(
                    color: Color.black.opacity(0.24),
                    radius: 10,
                    y: 3
                )
            }
            .frame(
                width: proxy.size.width,
                height: 344
            )
            .clipped()
        }
        .frame(height: 344)
        .clipped()
    }

    private var goalFlowHeader: some View {
        ZStack {
            HStack {
                Button {
                    withAnimation(
                        .snappy(duration: 0.22)
                    ) {
                        step = max(0, step - 1)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(
                            .system(
                                size: 15,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .frame(
                            width: 40,
                            height: 40
                        )
                        .background(
                            Color.white.opacity(0.90),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(
                                    Color.black.opacity(0.05),
                                    lineWidth: 0.7
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ATHLTHLocalization.format(
                        english: "Back",
                        norwegian: "Tilbake"
                    )
                )

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(
                        ATHLTHLocalization.format(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    )
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
            }

            Text(
                ATHLTHLocalization.format(
                    english: "Create Goal",
                    norwegian: "Opprett mål"
                )
            )
            .font(.headline.weight(.bold))
            .foregroundStyle(
                ATHLTHTheme.primaryText
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var goalImageButtonTitle: String {
        imageData == nil
            ? "Choose from Photos"
            : "Change photo"
    }

    private var progressHeader: some View {
        VStack(spacing: 7) {
            HStack {
                Text(
                    ATHLTHLocalization.format(
                        english: "Step %d of 5",
                        norwegian: "Steg %d av 5",
                        step + 1
                    )
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )

                Spacer()

                Text(stepTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
            }

            ProgressView(
                value: Double(step + 1),
                total: 5
            )
            .tint(ATHLTHTheme.accentDeep)
            .scaleEffect(
                x: 1,
                y: 0.72,
                anchor: .center
            )
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
    }

    private var categoryStep: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(
                GoalCategory.allCases
            ) { option in
                let isSelected =
                    category == option
                let tint =
                    goalCategoryTint(option)

                Button {
                    withAnimation(
                        .snappy(duration: 0.20)
                    ) {
                        category = option
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(
                            systemName:
                                option.systemImage
                        )
                        .font(
                            .system(
                                size: 20,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            isSelected
                                ? .white
                                : tint
                        )
                        .frame(
                            width: 54,
                            height: 54
                        )
                        .background(
                            isSelected
                                ? goalFlowBlue
                                : tint.opacity(0.11),
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(option.title)
                                .font(
                                    .system(
                                        size: 17,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.86)

                            Text(option.subtitle)
                                .font(
                                    .system(
                                        size: 13.2,
                                        weight: .regular
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )
                                .lineLimit(2)
                                .multilineTextAlignment(
                                    .leading
                                )
                        }

                        Spacer(minLength: 8)

                        ZStack {
                            Circle()
                                .stroke(
                                    isSelected
                                        ? goalFlowBlue
                                        : Color.black.opacity(0.16),
                                    lineWidth:
                                        isSelected
                                            ? 1.8
                                            : 1.2
                                )
                                .frame(
                                    width: 29,
                                    height: 29
                                )

                            if isSelected {
                                Circle()
                                    .fill(
                                        goalFlowBlue
                                    )
                                    .frame(
                                        width: 29,
                                        height: 29
                                    )

                                Image(
                                    systemName:
                                        "checkmark"
                                )
                                .font(
                                    .system(
                                        size: 12,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    .white
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 78
                    )
                    .background(
                        isSelected
                            ? goalFlowBlueSoft
                            : Color.white.opacity(0.98),
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
                            isSelected
                                ? goalFlowBlue
                                : Color.black.opacity(0.055),
                            lineWidth:
                                isSelected
                                    ? 1.55
                                    : 0.8
                        )
                    }
                    .shadow(
                        color:
                            Color.black.opacity(
                                isSelected
                                    ? 0.07
                                    : 0.045
                            ),
                        radius:
                            isSelected
                                ? 13
                                : 10,
                        y: 5
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func goalCategoryTint(
        _ category: GoalCategory
    ) -> Color {
        switch category {
        case .event:
            return Color(
                red: 0.18,
                green: 0.39,
                blue: 0.67
            )
        case .endurance:
            return goalFlowBlue
        case .strength:
            return Color(
                red: 0.13,
                green: 0.20,
                blue: 0.34
            )
        case .body:
            return Color(
                red: 0.16,
                green: 0.56,
                blue: 0.40
            )
        case .consistency:
            return Color(
                red: 0.38,
                green: 0.32,
                blue: 0.74
            )
        case .recovery:
            return Color(
                red: 0.24,
                green: 0.36,
                blue: 0.68
            )
        case .custom:
            return Color(
                red: 0.28,
                green: 0.34,
                blue: 0.46
            )
        }
    }

    @ViewBuilder
    private var targetStep: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            goalInputCard(
                icon: "text.cursor",
                title:
                    ATHLTHLocalization.format(
                        english: "Goal name",
                        norwegian: "Navn på målet"
                    )
            ) {
                TextField(
                    ATHLTHLocalization.format(
                        english: "Optional — ATHLTH can name it for you",
                        norwegian: "Valgfritt – ATHLTH kan navngi det for deg"
                    ),
                    text: $title
                )
                .font(.subheadline)
                .textInputAutocapitalization(
                    .sentences
                )
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(
                    Color.black.opacity(0.035),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
            }

            switch category {
            case .event:
                goalNumberField(
                    title:
                        ATHLTHLocalization.format(
                            english: "Event distance",
                            norwegian: "Distanse"
                        ),
                    suffix: "km",
                    icon: "flag.checkered",
                    value: $targetValue
                )

                goalTrackingNote(
                    icon: "heart.fill",
                    title:
                        ATHLTHLocalization.format(
                            english: "Apple Health verifies training distance",
                            norwegian: "Apple Health verifiserer treningsdistanse"
                        ),
                    detail:
                        ATHLTHLocalization.format(
                            english: "The event itself remains a manual completion.",
                            norwegian: "Selve arrangementet fullføres manuelt."
                        )
                )

            case .endurance:
                goalInputCard(
                    icon: "figure.run",
                    title:
                        ATHLTHLocalization.format(
                            english: "Activity",
                            norwegian: "Aktivitet"
                        )
                ) {
                    goalActivitySelector
                }

                goalNumberField(
                    title:
                        ATHLTHLocalization.format(
                            english: "Target distance",
                            norwegian: "Måldistanse"
                        ),
                    suffix: "km",
                    icon: activityGoalIcon,
                    value: $targetValue
                )

                goalTrackingNote(
                    icon: "heart.fill",
                    title:
                        ATHLTHLocalization.format(
                            english: "Tracked automatically",
                            norwegian: "Spores automatisk"
                        ),
                    detail:
                        ATHLTHLocalization.format(
                            english: "Only qualifying workouts recorded after the goal is created count.",
                            norwegian: "Kun kvalifiserende økter registrert etter at målet er opprettet teller."
                        )
                )

            case .strength:
                goalInputCard(
                    icon: "dumbbell.fill",
                    title:
                        ATHLTHLocalization.format(
                            english: "Exercise",
                            norwegian: "Øvelse"
                        )
                ) {
                    VStack(spacing: 10) {
                        Button {
                            showingExercisePicker = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(
                                    systemName:
                                        "list.bullet.rectangle"
                                )
                                .font(
                                    .system(
                                        size: 14,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        ATHLTHLocalization.format(
                                            english:
                                                "Choose from exercise library",
                                            norwegian:
                                                "Velg fra øvelseslisten"
                                        )
                                    )
                                    .font(
                                        .caption
                                            .weight(.semibold)
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

                                    if !exerciseName
                                        .trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        )
                                        .isEmpty {
                                        Text(exerciseName)
                                            .font(.caption2)
                                            .foregroundStyle(
                                                .secondary
                                            )
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(
                                    systemName:
                                        "chevron.right"
                                )
                                .font(
                                    .caption.weight(.bold)
                                )
                                .foregroundStyle(
                                    .tertiary
                                )
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 52)
                            .background(
                                goalFlowBlueSoft.opacity(
                                    0.72
                                ),
                                in: RoundedRectangle(
                                    cornerRadius: 13,
                                    style: .continuous
                                )
                            )
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(
                                    Color.black.opacity(
                                        0.07
                                    )
                                )
                                .frame(height: 0.5)

                            Text(
                                ATHLTHLocalization.format(
                                    english: "or enter your own",
                                    norwegian: "eller skriv inn selv"
                                )
                            )
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .fixedSize()

                            Rectangle()
                                .fill(
                                    Color.black.opacity(
                                        0.07
                                    )
                                )
                                .frame(height: 0.5)
                        }

                        TextField(
                            ATHLTHLocalization.format(
                                english:
                                    "Custom exercise name",
                                norwegian:
                                    "Skriv inn øvelse"
                            ),
                            text: $exerciseName
                        )
                        .font(.subheadline)
                        .textInputAutocapitalization(
                            .words
                        )
                        .autocorrectionDisabled(false)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(
                            Color.black.opacity(0.035),
                            in: RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                    }
                }

                goalNumberField(
                    title:
                        ATHLTHLocalization.format(
                            english: "Target weight",
                            norwegian: "Målvekt"
                        ),
                    suffix: "kg",
                    icon: "scalemass.fill",
                    value: $targetValue
                )

                goalTrackingNote(
                    icon: "a.circle.fill",
                    title:
                        ATHLTHLocalization.format(
                            english: "Tracked from ATHLTH sets",
                            norwegian: "Spores fra sett i ATHLTH"
                        ),
                    detail:
                        ATHLTHLocalization.format(
                            english: "Only sets logged after the goal is created can complete milestones.",
                            norwegian: "Kun sett logget etter at målet er opprettet kan fullføre delmål."
                        )
                )

            case .body:
                goalNumberField(
                    title:
                        ATHLTHLocalization.format(
                            english: "Target weight",
                            norwegian: "Målvekt"
                        ),
                    suffix: "kg",
                    icon: "scalemass.fill",
                    value: $targetValue
                )

                if let current =
                        health.personalDetails
                            .weightKilograms {
                    goalTrackingNote(
                        icon: "heart.fill",
                        title:
                            ATHLTHLocalization.format(
                                english: "Apple Health baseline",
                                norwegian: "Utgangspunkt fra Apple Health"
                            ),
                        detail:
                            ATHLTHLocalization.format(
                                english: "Current weight: %.1f kg. New samples are measured from this baseline.",
                                norwegian: "Nåværende vekt: %.1f kg. Nye målinger vurderes fra dette utgangspunktet.",
                                current
                            )
                    )
                } else {
                    goalTrackingNote(
                        icon: "exclamationmark.circle.fill",
                        title:
                            ATHLTHLocalization.format(
                                english: "No weight baseline yet",
                                norwegian: "Ingen vektmåling tilgjengelig ennå"
                            ),
                        detail:
                            ATHLTHLocalization.format(
                                english: "You can create the goal now. Tracking stays manual until Apple Health has a baseline.",
                                norwegian: "Du kan opprette målet nå. Sporingen er manuell til Apple Health har et utgangspunkt."
                            )
                    )
                }

            case .consistency:
                goalNumberField(
                    title:
                        ATHLTHLocalization.format(
                            english: "Workout target",
                            norwegian: "Antall økter"
                        ),
                    suffix:
                        ATHLTHLocalization.format(
                            english: "workouts",
                            norwegian: "økter"
                        ),
                    icon: "calendar.badge.checkmark",
                    value: $targetValue
                )

                goalTrackingNote(
                    icon: "heart.fill",
                    title:
                        ATHLTHLocalization.format(
                            english: "Counts new workouts",
                            norwegian: "Teller nye treningsøkter"
                        ),
                    detail:
                        ATHLTHLocalization.format(
                            english: "Only workouts recorded after the goal starts are included.",
                            norwegian: "Kun økter registrert etter at målet starter blir tatt med."
                        )
                )

            case .recovery:
                goalNumberField(
                    title:
                        ATHLTHLocalization.format(
                            english: "Sleep target",
                            norwegian: "Søvnmål"
                        ),
                    suffix:
                        ATHLTHLocalization.format(
                            english: "hours",
                            norwegian: "timer"
                        ),
                    icon: "moon.stars.fill",
                    value: $targetValue
                )

                goalTrackingNote(
                    icon: "heart.fill",
                    title:
                        ATHLTHLocalization.format(
                            english: "Uses Apple Health sleep",
                            norwegian: "Bruker søvn fra Apple Health"
                        ),
                    detail:
                        ATHLTHLocalization.format(
                            english: "A qualifying night can complete the goal automatically.",
                            norwegian: "En kvalifiserende natt kan fullføre målet automatisk."
                        )
                )

            case .custom:
                goalTrackingNote(
                    icon: "hand.tap.fill",
                    title:
                        ATHLTHLocalization.format(
                            english: "Manual tracking",
                            norwegian: "Manuell sporing"
                        ),
                    detail:
                        ATHLTHLocalization.format(
                            english: "Add your own milestones and mark them complete when you are ready.",
                            norwegian: "Legg til egne delmål og marker dem som fullført når du er klar."
                        )
                )
            }
        }
    }

    private var identityStep: some View {
        let imageButtonTitle =
            goalImageButtonTitle

        return VStack(
            alignment: .leading,
            spacing: 14
        ) {
            goalInputCard(
                icon: "calendar",
                title:
                    ATHLTHLocalization.format(
                        english: "Deadline",
                        norwegian: "Frist"
                    )
            ) {
                VStack(spacing: 10) {
                    Toggle(
                        ATHLTHLocalization.format(
                            english: "Use a target date",
                            norwegian: "Bruk en måldato"
                        ),
                        isOn: $hasDeadline
                    )
                    .disabled(
                        category == .event
                    )
                    .font(.subheadline.weight(.semibold))

                    if hasDeadline ||
                        category == .event {
                        Divider()
                            .opacity(0.45)

                        DatePicker(
                            ATHLTHLocalization.format(
                                english: "Target date",
                                norwegian: "Måldato"
                            ),
                            selection: $deadline,
                            in:
                                Calendar.current
                                    .startOfDay(
                                        for: Date()
                                    )...,
                            displayedComponents:
                                .date
                        )
                        .font(.subheadline)
                    }
                }
            }

            goalInputCard(
                icon: "photo.fill",
                title:
                    ATHLTHLocalization.format(
                        english: "Goal image",
                        norwegian: "Målbilde"
                    )
            ) {
                VStack(spacing: 10) {
                    if let imageData,
                       let image =
                            UIImage(
                                data: imageData
                            ) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 150)
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style:
                                        .continuous
                                )
                            )
                    }

                    PhotosPicker(
                        selection:
                            $selectedPhoto,
                        matching: .images
                    ) {
                        HStack(spacing: 8) {
                            Image(
                                systemName:
                                    "photo.on.rectangle.angled"
                            )

                            Text(
                                imageButtonTitle
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                            Spacer()

                            Image(
                                systemName:
                                    "chevron.right"
                            )
                            .font(
                                .caption.bold()
                            )
                        }
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .padding(
                            .horizontal,
                            12
                        )
                        .frame(height: 42)
                        .background(
                            Color.black
                                .opacity(
                                    0.035
                                ),
                            in:
                                RoundedRectangle(
                                    cornerRadius:
                                        12,
                                    style:
                                        .continuous
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(
                        alignment: .leading,
                        spacing: 9
                    ) {
                        Text(
                            ATHLTHLocalization.format(
                                english: "Choose an ATHLTH cover",
                                norwegian: "Velg et ATHLTH-bilde"
                            )
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )

                        ScrollView(
                            .horizontal,
                            showsIndicators: false
                        ) {
                            HStack(spacing: 9) {
                                ForEach(
                                    GoalCoverStyle.allCases
                                ) { style in
                                    let isSelected =
                                        imageData == nil &&
                                        coverStyle == style

                                    Button {
                                        selectedPhoto = nil
                                        imageData = nil
                                        coverStyle = style
                                    } label: {
                                        ZStack(
                                            alignment:
                                                .bottomLeading
                                        ) {
                                            Image(
                                                style.assetName
                                            )
                                            .resizable()
                                            .interpolation(
                                                .high
                                            )
                                            .scaledToFill()
                                            .frame(
                                                width: 112,
                                                height: 72
                                            )
                                            .clipped()

                                            LinearGradient(
                                                colors: [
                                                    .clear,
                                                    .black.opacity(
                                                        0.62
                                                    )
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )

                                            Text(style.title)
                                                .font(
                                                    .system(
                                                        size: 10,
                                                        weight: .bold
                                                    )
                                                )
                                                .foregroundStyle(
                                                    .white
                                                )
                                                .padding(8)

                                            if isSelected {
                                                Image(
                                                    systemName:
                                                        "checkmark.circle.fill"
                                                )
                                                .font(
                                                    .system(
                                                        size: 17,
                                                        weight: .bold
                                                    )
                                                )
                                                .foregroundStyle(
                                                    .white
                                                )
                                                .padding(7)
                                                .frame(
                                                    maxWidth:
                                                        .infinity,
                                                    maxHeight:
                                                        .infinity,
                                                    alignment:
                                                        .topTrailing
                                                )
                                            }
                                        }
                                        .frame(
                                            width: 112,
                                            height: 72
                                        )
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: 14,
                                                style:
                                                    .continuous
                                            )
                                        )
                                        .overlay {
                                            RoundedRectangle(
                                                cornerRadius: 14,
                                                style:
                                                    .continuous
                                            )
                                            .stroke(
                                                isSelected
                                                    ? goalFlowBlue
                                                    : Color.black
                                                        .opacity(
                                                            0.06
                                                        ),
                                                lineWidth:
                                                    isSelected
                                                        ? 2
                                                        : 0.7
                                            )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            goalInputCard(
                icon: "heart.text.square.fill",
                title:
                    ATHLTHLocalization.format(
                        english: "Why it matters",
                        norwegian: "Hvorfor dette er viktig"
                    )
            ) {
                TextField(
                    ATHLTHLocalization.format(
                        english: "Optional",
                        norwegian: "Valgfritt"
                    ),
                    text: $whyItMatters,
                    axis: .vertical
                )
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(12)
                .background(
                    Color.black.opacity(0.035),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
            }

            goalInputCard(
                icon: "note.text",
                title:
                    ATHLTHLocalization.format(
                        english: "Notes",
                        norwegian: "Notater"
                    )
            ) {
                TextField(
                    ATHLTHLocalization.format(
                        english: "Optional",
                        norwegian: "Valgfritt"
                    ),
                    text: $notes,
                    axis: .vertical
                )
                .font(.subheadline)
                .lineLimit(2...4)
                .padding(12)
                .background(
                    Color.black.opacity(0.035),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
            }

            if let activePlan =
                    session.activePlan {
                goalInputCard(
                    icon:
                        "list.bullet.clipboard.fill",
                    title:
                        ATHLTHLocalization.format(
                            english: "Training plan",
                            norwegian: "Treningsplan"
                        )
                ) {
                    Toggle(
                        isOn:
                            $linkActivePlan
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                ATHLTHLocalization.format(
                                    english: "Link this goal",
                                    norwegian: "Knytt målet til planen"
                                )
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                            Text(
                                activePlan.title
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }
                    }
                }
            }
        }
    }

    private var milestoneStep: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(
                Array(
                    previewMilestones
                        .enumerated()
                ),
                id: \.element.id
            ) { index, milestone in
                let isFinal =
                    index ==
                    previewMilestones
                        .count - 1

                HStack(
                    alignment: .top,
                    spacing: 11
                ) {
                    ZStack {
                        Circle()
                            .fill(
                                isFinal
                                    ? ATHLTHTheme
                                        .accentDeep
                                    : ATHLTHTheme
                                        .accentSoft
                            )
                            .frame(
                                width: 34,
                                height: 34
                            )

                        if isFinal {
                            Image(
                                systemName:
                                    "flag.fill"
                            )
                            .font(
                                .system(
                                    size: 12,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                .white
                            )
                        } else {
                            Text(
                                "\(index + 1)"
                            )
                            .font(
                                .caption
                                    .weight(.bold)
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .accentDeep
                            )
                        }
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        HStack(
                            alignment:
                                .firstTextBaseline
                        ) {
                            Text(
                                milestone.title
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .bold
                                    )
                            )
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )
                            .fixedSize(
                                horizontal:
                                    false,
                                vertical: true
                            )

                            Spacer(
                                minLength: 8
                            )

                            if isFinal {
                                Text(
                                    ATHLTHLocalization.format(
                                        english: "FINAL",
                                        norwegian: "MÅL"
                                    )
                                )
                                .font(
                                    .system(
                                        size: 8,
                                        weight: .bold
                                    )
                                )
                                .tracking(0.7)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .accentDeep
                                )
                            }
                        }

                        Text(
                            milestone
                                .targetDescription
                        )
                        .font(
                            .system(
                                size: 11.5
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                        if let rule =
                                milestone
                                    .automationRule {
                            goalTrackingPill(
                                icon:
                                    rule
                                        .dataSource
                                        .systemImage,
                                text:
                                    ATHLTHLocalization.format(
                                        english: "Automatic · %@",
                                        norwegian: "Automatisk · %@",
                                        rule
                                            .dataSource
                                            .title
                                    ),
                                emphasized: true
                            )
                        } else {
                            goalTrackingPill(
                                icon:
                                    "hand.tap.fill",
                                text:
                                    ATHLTHLocalization.format(
                                        english: "Manual",
                                        norwegian: "Manuell"
                                    ),
                                emphasized:
                                    false
                            )
                        }
                    }
                }
                .padding(13)
                .background(
                    Color.white.opacity(
                        0.97
                    ),
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
                        isFinal
                            ? ATHLTHTheme
                                .accentDeep
                                .opacity(0.20)
                            : Color.black
                                .opacity(0.045),
                        lineWidth: 0.8
                    )
                }
                .shadow(
                    color: Color.black.opacity(0.035),
                    radius: 9,
                    y: 4
                )
            }

            goalTrackingNote(
                icon: "plus.circle.fill",
                title:
                    ATHLTHLocalization.format(
                        english: "You can add more later",
                        norwegian: "Du kan legge til flere senere"
                    ),
                detail:
                    ATHLTHLocalization.format(
                        english: "Manual milestones can be added or checked at any time.",
                        norwegian: "Manuelle delmål kan legges til eller markeres når som helst."
                    )
            )
        }
    }

    private var reviewStep: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            GoalPreviewCard(
                title: resolvedTitle,
                category: category,
                deadline:
                    (hasDeadline ||
                     category == .event)
                        ? deadline
                        : nil,
                coverStyle: coverStyle,
                imageData: imageData
            )

            goalInputCard(
                icon: "star.fill",
                title:
                    ATHLTHLocalization.format(
                        english: "Goal settings",
                        norwegian: "Målinnstillinger"
                    )
            ) {
                VStack(spacing: 11) {
                    Toggle(
                        ATHLTHLocalization.format(
                            english: "Make this my Primary Goal",
                            norwegian: "Gjør dette til hovedmålet mitt"
                        ),
                        isOn: $makePrimary
                    )
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )

                    Divider()
                        .opacity(0.45)

                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                ATHLTHLocalization.format(
                                    english: "Privacy",
                                    norwegian: "Synlighet"
                                )
                            )
                            .font(
                                .subheadline
                                    .weight(
                                        .semibold
                                    )
                            )

                            Text(
                                ATHLTHLocalization.format(
                                    english: "Who can see this goal",
                                    norwegian: "Hvem som kan se dette målet"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )
                        }

                        Spacer()

                        Picker(
                            "",
                            selection: $privacy
                        ) {
                            ForEach(
                                GoalPrivacy
                                    .allCases
                            ) { option in
                                Text(
                                    option.title
                                )
                                .tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }

            goalReviewSummaryCard

            goalTrackingNote(
                icon:
                    "checkmark.shield.fill",
                title:
                    ATHLTHLocalization.format(
                        english: "Safe automation",
                        norwegian: "Trygg automatikk"
                    ),
                detail:
                    ATHLTHLocalization.format(
                        english: "Automatic milestones only use qualifying data recorded after this goal is created. You can always override a milestone manually.",
                        norwegian: "Automatiske delmål bruker bare kvalifiserende data registrert etter at målet er opprettet. Du kan alltid overstyre et delmål manuelt."
                    )
            )
        }
    }

    private func goalStepHeading(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text(title)
                .font(
                    .system(
                        size: 22,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

            Text(subtitle)
                .font(
                    .system(
                        size: 12.5
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
        .padding(.bottom, 2)
    }

    private func goalInputCard<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content:
            () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack(spacing: 10) {
                Image(
                    systemName: icon
                )
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .frame(
                    width: 34,
                    height: 34
                )
                .background(
                    ATHLTHTheme
                        .accentSoft
                        .opacity(0.80),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

                Text(title)
                    .font(
                        .system(
                            size: 13,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Spacer()
            }

            content()
        }
        .padding(14)
        .background(
            Color.white.opacity(0.97),
            in: RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 21,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.052),
                lineWidth: 0.75
            )
        }
        .shadow(
            color: Color.black.opacity(0.035),
            radius: 9,
            y: 4
        )
    }

    private func goalNumberField(
        title: String,
        suffix: String,
        icon: String,
        value: Binding<Double>
    ) -> some View {
        goalInputCard(
            icon: icon,
            title: title
        ) {
            HStack(
                alignment:
                    .firstTextBaseline,
                spacing: 10
            ) {
                TextField(
                    "0",
                    value: value,
                    format:
                        .number.precision(
                            .fractionLength(
                                0...3
                            )
                        )
                )
                .keyboardType(
                    .decimalPad
                )
                .font(
                    .system(
                        size: 32,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .minimumScaleFactor(
                    0.72
                )

                Text(suffix)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
            }
            .padding(.horizontal, 14)
            .frame(height: 62)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme
                            .accentSoft
                            .opacity(0.50),
                        Color.black
                            .opacity(0.025)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
                .stroke(
                    ATHLTHTheme
                        .accentDeep
                        .opacity(0.10),
                    lineWidth: 0.8
                )
            }
        }
    }

    private var goalActivitySelector:
        some View {
        HStack(spacing: 6) {
            goalActivityButton(
                .running,
                icon: "figure.run"
            )
            goalActivityButton(
                .walking,
                icon: "figure.walk"
            )
            goalActivityButton(
                .cycling,
                icon: "bicycle"
            )
            goalActivityButton(
                .hiking,
                icon: "mountain.2.fill"
            )
        }
    }

    private func goalActivityButton(
        _ option: GoalActivityFilter,
        icon: String
    ) -> some View {
        let isSelected =
            activity == option

        return Button {
            withAnimation(
                .snappy(duration: 0.18)
            ) {
                activity = option
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )

                Text(
                    option.title
                )
                .font(
                    .system(
                        size: 9.5,
                        weight: .semibold
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.7
                )
            }
            .foregroundStyle(
                isSelected
                    ? .white
                    : ATHLTHTheme
                        .primaryText
            )
            .frame(
                maxWidth: .infinity
            )
            .frame(height: 58)
            .background(
                isSelected
                    ? ATHLTHTheme
                        .accentDeep
                    : Color.black
                        .opacity(0.03),
                in: RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .stroke(
                    isSelected
                        ? ATHLTHTheme
                            .accentDeep
                        : Color.black
                            .opacity(0.045),
                    lineWidth:
                        isSelected
                            ? 1
                            : 0.7
                )
            }
            .shadow(
                color:
                    isSelected
                        ? ATHLTHTheme
                            .accentDeep
                            .opacity(0.16)
                        : Color.clear,
                radius: 8,
                y: 3
            )
        }
        .buttonStyle(.plain)
    }

    private var activityGoalIcon:
        String {
        switch activity {
        case .running:
            return "figure.run"
        case .walking:
            return "figure.walk"
        case .cycling:
            return "bicycle"
        case .hiking:
            return "mountain.2.fill"
        case .any:
            return "figure.mixed.cardio"
        }
    }

    private func goalTrackingNote(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 11
        ) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 14,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 36,
                height: 36
            )
            .background(
                Color.white.opacity(0.72),
                in: RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        .system(
                            size: 12,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(detail)
                    .font(
                        .system(
                            size: 11.5
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer(
                minLength: 0
            )
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    ATHLTHTheme
                        .accentSoft
                        .opacity(0.62),
                    ATHLTHTheme
                        .accentSoft
                        .opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                ATHLTHTheme
                    .accentDeep
                    .opacity(0.08),
                lineWidth: 0.7
            )
        }
    }

    private func goalTrackingPill(
        icon: String,
        text: String,
        emphasized: Bool
    ) -> some View {
        Label(
            text,
            systemImage: icon
        )
        .font(
            .system(
                size: 9,
                weight: .semibold
            )
        )
        .foregroundStyle(
            emphasized
                ? ATHLTHTheme
                    .accentDeep
                : ATHLTHTheme
                    .mutedText
        )
        .padding(
            .horizontal,
            8
        )
        .frame(height: 24)
        .background(
            emphasized
                ? ATHLTHTheme
                    .accentSoft
                : Color.black
                    .opacity(0.035),
            in: Capsule()
        )
    }

    private var goalReviewSummaryCard:
        some View {
        let source: GoalDataSource

        switch category {
        case .strength:
            source = .athlth
        case .custom:
            source = .manual
        default:
            source = .appleHealth
        }

        return VStack(
            spacing: 0
        ) {
            goalReviewRow(
                icon:
                    source.systemImage,
                title:
                    ATHLTHLocalization.format(
                        english: "Tracking",
                        norwegian: "Sporing"
                    ),
                value: source.title
            )

            Divider()
                .padding(.leading, 42)
                .opacity(0.45)

            goalReviewRow(
                icon:
                    "point.3.connected.trianglepath.dotted",
                title:
                    ATHLTHLocalization.format(
                        english: "Milestones",
                        norwegian: "Delmål"
                    ),
                value:
                    "\(previewMilestones.count)"
            )

            if hasDeadline ||
                category == .event {
                Divider()
                    .padding(
                        .leading,
                        42
                    )
                    .opacity(0.45)

                goalReviewRow(
                    icon: "calendar",
                    title:
                        ATHLTHLocalization.format(
                            english: "Deadline",
                            norwegian: "Frist"
                        ),
                    value:
                        deadline.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                )
            }

            if linkActivePlan,
               let activePlan =
                    session.activePlan {
                Divider()
                    .padding(
                        .leading,
                        42
                    )
                    .opacity(0.45)

                goalReviewRow(
                    icon:
                        "list.bullet.clipboard.fill",
                    title:
                        ATHLTHLocalization.format(
                            english: "Plan",
                            norwegian: "Plan"
                        ),
                    value:
                        activePlan.title
                )
            }
        }
        .padding(.horizontal, 13)
        .background(
            Color.white.opacity(0.92),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(
                    0.045
                ),
                lineWidth: 0.7
            )
        }
    }

    private func goalReviewRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 13,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )
            .frame(
                width: 32,
                height: 32
            )
            .background(
                ATHLTHTheme
                    .accentSoft,
                in: RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )

            Text(title)
                .font(
                    .subheadline
                        .weight(
                            .semibold
                        )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme
                        .mutedText
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.75
                )
        }
        .padding(.vertical, 10)
    }

    private var footer: some View {
        Button {
            if step == 4 {
                createGoal()
            } else {
                withAnimation(
                    .snappy(duration: 0.22)
                ) {
                    step += 1
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(
                    step == 4
                        ? ATHLTHLocalization.format(
                            english: "Create Goal",
                            norwegian: "Opprett mål"
                        )
                        : ATHLTHLocalization.format(
                            english: "Continue",
                            norwegian: "Fortsett"
                        )
                )
                .font(
                    .system(
                        size: 17,
                        weight: .bold
                    )
                )

                Image(
                    systemName:
                        step == 4
                            ? "checkmark"
                            : "arrow.right"
                )
                .font(
                    .system(
                        size: 14,
                        weight: .bold
                    )
                )
            }
            .foregroundStyle(.white)
            .frame(
                maxWidth: .infinity,
                minHeight: 58
            )
            .background(
                LinearGradient(
                    colors:
                        canContinue
                            ? [
                                Color(
                                    red: 0.20,
                                    green: 0.60,
                                    blue: 1.0
                                ),
                                Color(
                                    red: 0.10,
                                    green: 0.46,
                                    blue: 0.95
                                )
                            ]
                            : [
                                Color.secondary.opacity(0.28),
                                Color.secondary.opacity(0.28)
                            ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
            .shadow(
                color:
                    canContinue
                        ? goalFlowBlue.opacity(0.24)
                        : Color.clear,
                radius: 16,
                y: 6
            )
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            Color.white.opacity(0.97)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    Color.black.opacity(0.04)
                )
                .frame(height: 0.5)
        }
    }

    private var stepTitle: String {
        switch step {
        case 0:
            return ATHLTHLocalization.format(
                english: "Goal type",
                norwegian: "Måltype"
            )
        case 1:
            return ATHLTHLocalization.format(
                english: "Target",
                norwegian: "Mål"
            )
        case 2:
            return ATHLTHLocalization.format(
                english: "Details",
                norwegian: "Detaljer"
            )
        case 3:
            return ATHLTHLocalization.format(
                english: "Milestones",
                norwegian: "Delmål"
            )
        default:
            return ATHLTHLocalization.format(
                english: "Review",
                norwegian: "Oppsummering"
            )
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            return true
        case 1:
            if category == .custom { return !resolvedTitle.isEmpty }
            if category == .strength {
                return targetValue > 0 && !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return targetValue > 0
        default:
            return true
        }
    }

    private var resolvedTitle: String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { return cleaned }

        switch category {
        case .event: return "My Event"
        case .endurance: return "\(activity.title) \(targetValue.cleanNumber) km"
        case .strength: return "\(exerciseName) \(targetValue.cleanNumber) kg"
        case .body: return "Reach \(targetValue.cleanNumber) kg"
        case .consistency: return "Complete \(targetValue.cleanNumber) workouts"
        case .recovery: return "Sleep \(targetValue.cleanNumber) hours"
        case .custom: return ""
        }
    }

    private var previewMilestones: [GoalMilestone] {
        makeMilestones(createdAt: Date())
    }

    private func createGoal() {
        let now = Date()
        let goalID = UUID()
        let baselineWeight = health.personalDetails.weightKilograms

        let source: GoalDataSource
        switch category {
        case .strength:
            source = .athlth
        case .custom:
            source = .manual
        default:
            source = .appleHealth
        }

        let target: GoalTarget?
        switch category {
        case .body:
            target = GoalTarget(
                metric: .bodyWeightKilograms,
                targetValue: targetValue,
                unit: "kg",
                baselineValue: baselineWeight
            )
        case .endurance, .event:
            target = GoalTarget(
                metric: .singleWorkoutDistanceMeters,
                targetValue: targetValue * 1_000,
                unit: "m",
                activity: category == .event ? .running : activity
            )
        case .strength:
            target = GoalTarget(
                metric: .strengthWeightKilograms,
                targetValue: targetValue,
                unit: "kg",
                exerciseName: exerciseName
            )
        case .consistency:
            target = GoalTarget(
                metric: .workoutCount,
                targetValue: targetValue,
                unit: "workouts",
                activity: .any
            )
        case .recovery:
            target = GoalTarget(
                metric: .sleepDurationSeconds,
                targetValue: targetValue * 3_600,
                unit: "seconds"
            )
        case .custom:
            target = nil
        }

        var goal = ATHLTHGoal(
            id: goalID,
            title: resolvedTitle,
            category: category,
            createdAt: now,
            startDate: now,
            deadline: (hasDeadline || category == .event) ? deadline : nil,
            coverStyle: coverStyle,
            whyItMatters: whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            privacy: privacy,
            isPrimary: makePrimary,
            dataSource: source,
            target: target,
            milestones: makeMilestones(createdAt: now),
            linkedTrainingPlanID: linkActivePlan ? session.activePlan?.id : nil
        )

        if let imageData,
           let filename = try? goalStore.saveImageData(imageData, for: goalID) {
            goal.imageFilename = filename
        }

        goalStore.add(goal)
        dismiss()
    }

    private func makeMilestones(createdAt: Date) -> [GoalMilestone] {
        switch category {
        case .event:
            let distanceMeters = targetValue * 1_000
            var milestones: [GoalMilestone] = []

            for fraction in [0.25, 0.50, 0.75] {
                let meters = distanceMeters * fraction
                guard meters >= 2_000 else { continue }
                milestones.append(
                    GoalMilestone(
                        createdAt: createdAt,
                        title: "Complete \((meters / 1_000).cleanNumber) km in training",
                        targetDescription: "A qualifying run after goal creation",
                        automationRule: GoalAutomationRule(
                            dataSource: .appleHealth,
                            metric: .singleWorkoutDistanceMeters,
                            comparison: .atLeast,
                            targetValue: meters,
                            activity: .running
                        )
                    )
                )
            }

            milestones.append(
                GoalMilestone(
                    createdAt: createdAt,
                    title: "Complete the event",
                    targetDescription: "Check this when the event itself is completed",
                    completesGoal: true
                )
            )
            return milestones

        case .endurance:
            let meters = targetValue * 1_000
            let fractions = [0.50, 0.75, 1.0]

            return fractions.enumerated().map { index, fraction in
                let milestoneMeters = meters * fraction
                return GoalMilestone(
                    createdAt: createdAt,
                    title: "\(activity.title) \((milestoneMeters / 1_000).cleanNumber) km",
                    targetDescription: "Single qualifying workout",
                    automationRule: GoalAutomationRule(
                        dataSource: .appleHealth,
                        metric: .singleWorkoutDistanceMeters,
                        comparison: .atLeast,
                        targetValue: milestoneMeters,
                        activity: activity
                    ),
                    completesGoal: index == fractions.count - 1
                )
            }

        case .strength:
            let targets = [0.80, 0.90, 1.0].map { targetValue * $0 }

            return targets.enumerated().map { index, weight in
                GoalMilestone(
                    createdAt: createdAt,
                    title: "\(exerciseName) \(weight.cleanNumber) kg",
                    targetDescription: "Logged set in ATHLTH after goal creation",
                    automationRule: GoalAutomationRule(
                        dataSource: .athlth,
                        metric: .strengthWeightKilograms,
                        comparison: .atLeast,
                        targetValue: weight,
                        exerciseName: exerciseName
                    ),
                    completesGoal: index == targets.count - 1
                )
            }

        case .body:
            guard let baseline = health.personalDetails.weightKilograms else {
                return [
                    GoalMilestone(
                        createdAt: createdAt,
                        title: "Reach \(targetValue.cleanNumber) kg",
                        targetDescription: "Manual until an Apple Health baseline is available",
                        completesGoal: true
                    )
                ]
            }

            let difference = targetValue - baseline
            guard abs(difference) >= 0.2 else {
                return [
                    GoalMilestone(
                        createdAt: createdAt,
                        title: "Maintain \(targetValue.cleanNumber) kg",
                        targetDescription: "New Apple Health weight sample",
                        automationRule: GoalAutomationRule(
                            dataSource: .appleHealth,
                            metric: .bodyWeightKilograms,
                            comparison: difference <= 0 ? .atMost : .atLeast,
                            targetValue: targetValue,
                            baselineValue: baseline
                        ),
                        completesGoal: true
                    )
                ]
            }

            let halfway = baseline + difference * 0.5
            let comparison: GoalComparison = difference < 0 ? .atMost : .atLeast

            return [
                GoalMilestone(
                    createdAt: createdAt,
                    title: "Reach \(halfway.cleanNumber) kg",
                    targetDescription: "Halfway from \(baseline.cleanNumber) kg",
                    automationRule: GoalAutomationRule(
                        dataSource: .appleHealth,
                        metric: .bodyWeightKilograms,
                        comparison: comparison,
                        targetValue: halfway,
                        baselineValue: baseline
                    )
                ),
                GoalMilestone(
                    createdAt: createdAt,
                    title: "Reach \(targetValue.cleanNumber) kg",
                    targetDescription: "Target weight",
                    automationRule: GoalAutomationRule(
                        dataSource: .appleHealth,
                        metric: .bodyWeightKilograms,
                        comparison: comparison,
                        targetValue: targetValue,
                        baselineValue: baseline
                    ),
                    completesGoal: true
                )
            ]

        case .consistency:
            let total = max(Int(targetValue.rounded()), 1)
            let values = Array(Set([max(1, total / 3), max(1, total * 2 / 3), total])).sorted()

            return values.enumerated().map { index, count in
                GoalMilestone(
                    createdAt: createdAt,
                    title: "Complete \(count) workouts",
                    targetDescription: "Workouts recorded after goal creation",
                    automationRule: GoalAutomationRule(
                        dataSource: .appleHealth,
                        metric: .workoutCount,
                        comparison: .atLeast,
                        targetValue: Double(count),
                        activity: .any
                    ),
                    completesGoal: index == values.count - 1
                )
            }

        case .recovery:
            let seconds = targetValue * 3_600
            return [
                GoalMilestone(
                    createdAt: createdAt,
                    title: "Sleep \(targetValue.cleanNumber) hours",
                    targetDescription: "A qualifying night recorded after goal creation",
                    automationRule: GoalAutomationRule(
                        dataSource: .appleHealth,
                        metric: .sleepDurationSeconds,
                        comparison: .atLeast,
                        targetValue: seconds
                    ),
                    completesGoal: true
                )
            ]

        case .custom:
            return [
                GoalMilestone(
                    createdAt: createdAt,
                    title: "Complete goal",
                    targetDescription: "Manual milestone",
                    completesGoal: true
                )
            ]
        }
    }

    private func applyDefaults(for category: GoalCategory) {
        switch category {
        case .event:
            targetValue = 42.195
            hasDeadline = true
            coverStyle = .summit
        case .endurance:
            targetValue = 5
            hasDeadline = true
            coverStyle = .track
        case .strength:
            targetValue = 100
            hasDeadline = true
            coverStyle = .strength
        case .body:
            targetValue = max((health.personalDetails.weightKilograms ?? 84) - 4, 1)
            hasDeadline = true
            coverStyle = .forest
        case .consistency:
            targetValue = 12
            hasDeadline = true
            coverStyle = .forest
        case .recovery:
            targetValue = 8
            hasDeadline = false
            coverStyle = .calm
        case .custom:
            targetValue = 1
            hasDeadline = false
            coverStyle = .forest
        }
    }

    private func numberField(
        title: String,
        suffix: String,
        value: Binding<Double>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...3)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
        .padding()
        .goalCard()
    }
}

private struct GoalExercisePickerSheet:
    View {
    @Environment(\.dismiss)
    private var dismiss
    @EnvironmentObject
    private var library: ExerciseLibraryStore

    let currentName: String
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var customName = ""

    private var results:
        [ExerciseLibraryEntry] {
        Array(
            library
                .search(query: query)
                .prefix(80)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 9) {
                        Image(
                            systemName:
                                "magnifyingglass"
                        )
                        .foregroundStyle(.secondary)

                        TextField(
                            ATHLTHLocalization.format(
                                english:
                                    "Search exercises",
                                norwegian:
                                    "Søk etter øvelse"
                            ),
                            text: $query
                        )
                        .textInputAutocapitalization(
                            .never
                        )
                        .autocorrectionDisabled()

                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(
                                    systemName:
                                        "xmark.circle.fill"
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(
                        Color(
                            .secondarySystemGroupedBackground
                        ),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                    HStack(spacing: 8) {
                        TextField(
                            ATHLTHLocalization.format(
                                english:
                                    "Or enter your own exercise",
                                norwegian:
                                    "Eller skriv inn egen øvelse"
                            ),
                            text: $customName
                        )
                        .textInputAutocapitalization(
                            .words
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(
                            Color(
                                .secondarySystemGroupedBackground
                            ),
                            in: RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )

                        Button {
                            choose(customName)
                        } label: {
                            Text(
                                ATHLTHLocalization.format(
                                    english: "Use",
                                    norwegian: "Bruk"
                                )
                            )
                            .font(
                                .caption.weight(.bold)
                            )
                            .padding(.horizontal, 13)
                            .frame(height: 42)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ATHLTHTheme.accent)
                        .disabled(
                            customName
                                .trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )
                                .isEmpty
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                Divider()

                if library.isLoading &&
                    results.isEmpty {
                    ProgressView(
                        ATHLTHLocalization.format(
                            english:
                                "Loading exercises…",
                            norwegian:
                                "Laster øvelser…"
                        )
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                } else if results.isEmpty {
                    ContentUnavailableView(
                        ATHLTHLocalization.format(
                            english:
                                "No matching exercises",
                            norwegian:
                                "Ingen øvelser funnet"
                        ),
                        systemImage: "dumbbell",
                        description: Text(
                            ATHLTHLocalization.format(
                                english:
                                    "Try another search or enter your own exercise above.",
                                norwegian:
                                    "Prøv et annet søk eller skriv inn egen øvelse over."
                            )
                        )
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results) {
                                entry in
                                Button {
                                    choose(
                                        entry.name
                                    )
                                } label: {
                                    HStack(
                                        spacing: 11
                                    ) {
                                        Image(
                                            systemName:
                                                "dumbbell.fill"
                                        )
                                        .font(
                                            .system(
                                                size: 13,
                                                weight:
                                                    .semibold
                                            )
                                        )
                                        .foregroundStyle(
                                            ATHLTHTheme
                                                .accentDeep
                                        )
                                        .frame(
                                            width: 34,
                                            height: 34
                                        )
                                        .background(
                                            ATHLTHTheme
                                                .accentSoft,
                                            in: RoundedRectangle(
                                                cornerRadius:
                                                    10,
                                                style:
                                                    .continuous
                                            )
                                        )

                                        VStack(
                                            alignment:
                                                .leading,
                                            spacing: 2
                                        ) {
                                            Text(
                                                entry.name
                                            )
                                            .font(
                                                .subheadline
                                                    .weight(
                                                        .semibold
                                                    )
                                            )
                                            .foregroundStyle(
                                                .primary
                                            )
                                            .lineLimit(1)

                                            let detail =
                                                [
                                                    entry
                                                        .bodyPart,
                                                    entry
                                                        .exercise
                                                        .equipment
                                                        .first
                                                ]
                                                .compactMap {
                                                    $0
                                                }
                                                .joined(
                                                    separator:
                                                        " · "
                                                )

                                            if !detail.isEmpty {
                                                Text(
                                                    detail
                                                )
                                                .font(
                                                    .caption2
                                                )
                                                .foregroundStyle(
                                                    .secondary
                                                )
                                                .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        if entry.name
                                            .caseInsensitiveCompare(
                                                currentName
                                            ) ==
                                            .orderedSame {
                                            Image(
                                                systemName:
                                                    "checkmark.circle.fill"
                                            )
                                            .foregroundStyle(
                                                ATHLTHTheme
                                                    .accent
                                            )
                                        } else {
                                            Image(
                                                systemName:
                                                    "chevron.right"
                                            )
                                            .font(
                                                .caption
                                            )
                                            .foregroundStyle(
                                                .tertiary
                                            )
                                        }
                                    }
                                    .padding(10)
                                    .background(
                                        Color(
                                            .secondarySystemGroupedBackground
                                        ),
                                        in: RoundedRectangle(
                                            cornerRadius:
                                                16,
                                            style:
                                                .continuous
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if results.count == 80 {
                                Text(
                                    ATHLTHLocalization.format(
                                        english:
                                            "Showing the first 80 matches. Search to narrow the list.",
                                        norwegian:
                                            "Viser de første 80 treffene. Søk for å snevre inn listen."
                                    )
                                )
                                .font(.caption2)
                                .foregroundStyle(
                                    .secondary
                                )
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            .background(
                Color(
                    .systemGroupedBackground
                )
                .ignoresSafeArea()
            )
            .navigationTitle(
                ATHLTHLocalization.format(
                    english: "Choose exercise",
                    norwegian: "Velg øvelse"
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button(
                        ATHLTHLocalization.format(
                            english: "Cancel",
                            norwegian: "Avbryt"
                        )
                    ) {
                        dismiss()
                    }
                }
            }
            .task {
                if customName.isEmpty {
                    customName =
                        currentName
                }
                await library.refresh()
            }
        }
    }

    private func choose(
        _ value: String
    ) {
        let cleaned =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !cleaned.isEmpty else {
            return
        }

        onSelect(cleaned)
        dismiss()
    }
}

struct GoalEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var session: AppSessionStore

    let goalID: UUID

    @State private var title = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var coverStyle: GoalCoverStyle = .forest
    @State private var whyItMatters = ""
    @State private var notes = ""
    @State private var privacy: GoalPrivacy = .privateOnly
    @State private var makePrimary = false
    @State private var linkActivePlan = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var didLoad = false

    private var goal: ATHLTHGoal? {
        goalStore.goals.first { $0.id == goalID }
    }

    var body: some View {
        let photoButtonTitle =
            imageData == nil
                ? "Choose or change photo"
                : "New photo selected"

        return NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Title", text: $title)

                    Toggle("Deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker(
                            "Target date",
                            selection: $deadline,
                            in: Calendar.current.startOfDay(for: Date())...,
                            displayedComponents: .date
                        )
                    }

                    Toggle("Primary Goal", isOn: $makePrimary)
                }

                Section("Identity") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(
                            photoButtonTitle,
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }

                    Picker("Fallback cover", selection: $coverStyle) {
                        ForEach(GoalCoverStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }

                    TextField("Why this matters", text: $whyItMatters, axis: .vertical)
                        .lineLimit(2...5)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let activePlan = session.activePlan {
                    Section("Training plan") {
                        Toggle(isOn: $linkActivePlan) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Link current plan")
                                Text(activePlan.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Privacy") {
                    Picker("Visibility", selection: $privacy) {
                        ForEach(GoalPrivacy.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                Section {
                    Text("Target rules and existing automatic milestones are kept unchanged when editing metadata. This prevents accidental changes to what counts as completion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                load()
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    imageData = try? await item?.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private func load() {
        guard !didLoad, let goal else { return }
        didLoad = true
        title = goal.title
        hasDeadline = goal.deadline != nil
        deadline = goal.deadline ?? Date()
        coverStyle = goal.coverStyle
        whyItMatters = goal.whyItMatters ?? ""
        notes = goal.notes ?? ""
        privacy = goal.privacy
        makePrimary = goal.isPrimary
        linkActivePlan = goal.linkedTrainingPlanID != nil
    }

    private func save() {
        guard var goal else { return }

        goal.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.deadline = hasDeadline ? deadline : nil
        goal.coverStyle = coverStyle
        goal.whyItMatters = whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        goal.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        goal.privacy = privacy
        goal.isPrimary = makePrimary
        goal.linkedTrainingPlanID = linkActivePlan ? session.activePlan?.id : nil

        if let imageData,
           let filename = try? goalStore.saveImageData(imageData, for: goal.id) {
            goal.imageFilename = filename
        }

        goalStore.update(goal)
        dismiss()
    }
}

private struct GoalPreviewCard: View {
    let title: String
    let category: GoalCategory
    let deadline: Date?
    let coverStyle: GoalCoverStyle
    let imageData: Data?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let imageData,
                   let image =
                        UIImage(
                            data: imageData
                        ) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: coverColors,
                        startPoint:
                            .topLeading,
                        endPoint:
                            .bottomTrailing
                    )
                }
            }
            .frame(height: 158)
            .clipped()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(
                        0.66
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                HStack {
                    Label(
                        category.title,
                        systemImage:
                            category
                                .systemImage
                    )
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .padding(
                        .horizontal,
                        9
                    )
                    .frame(height: 25)
                    .background(
                        Color.white
                            .opacity(
                                0.18
                            ),
                        in: Capsule()
                    )

                    Spacer()
                }

                Spacer()

                Text(title)
                    .font(
                        .system(
                            size: 21,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .lineLimit(2)

                if let deadline {
                    Label(
                        deadline.formatted(
                            date:
                                .abbreviated,
                            time: .omitted
                        ),
                        systemImage:
                            "calendar"
                    )
                    .font(
                        .system(
                            size: 10.5,
                            weight:
                                .medium
                        )
                    )
                }
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .frame(height: 158)
        .clipShape(
            RoundedRectangle(
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
                Color.white.opacity(
                    0.18
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color:
                Color.black.opacity(
                    0.06
                ),
            radius: 10,
            y: 4
        )
    }

    private var coverColors:
        [Color] {
        switch coverStyle {
        case .forest:
            return [
                ATHLTHTheme
                    .vitality
                    .opacity(0.86),
                Color.black
                    .opacity(0.78)
            ]
        case .summit:
            return [
                Color.blue
                    .opacity(0.78),
                Color.indigo
                    .opacity(0.84)
            ]
        case .track:
            return [
                Color.orange
                    .opacity(0.86),
                Color.red
                    .opacity(0.76)
            ]
        case .strength:
            return [
                Color.gray
                    .opacity(0.84),
                Color.black
                    .opacity(0.90)
            ]
        case .calm:
            return [
                Color.mint
                    .opacity(0.68),
                Color.blue
                    .opacity(0.68)
            ]
        }
    }
}

private extension View {
    func goalCard() -> some View {
        self
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            }
    }

    func goalHint() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ATHLTHTheme.accent.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

private extension Double {
    var cleanNumber: String {
        if abs(self - rounded()) < 0.001 {
            return String(Int(rounded()))
        }
        return String(format: "%.1f", self)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
