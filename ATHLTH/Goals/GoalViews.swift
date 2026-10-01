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
                LinearGradient(
                    colors: coverColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: goal.category.systemImage)
                        .font(.system(size: 64, weight: .medium))
                        .foregroundStyle(.white.opacity(0.20))
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                goalFlowHeader
                progressHeader

                ScrollView {
                    Group {
                        switch step {
                        case 0: categoryStep
                        case 1: targetStep
                        case 2: identityStep
                        case 3: milestoneStep
                        default: reviewStep
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)

                footer
            }
            .background(
                ATHLTHTheme.canvasTop
                    .ignoresSafeArea()
            )
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .onChange(of: category) { _, newValue in
                applyDefaults(for: newValue)
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    imageData = try? await item?.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private var goalFlowHeader: some View {
        ZStack {
            HStack {
                Button {
                    if step > 0 {
                        withAnimation(.snappy(duration: 0.22)) {
                            step -= 1
                        }
                    } else {
                        dismiss()
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
                            Color.white.opacity(0.86),
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
                    step > 0
                        ? ATHLTHLocalization.format(
                            english: "Back",
                            norwegian: "Tilbake"
                        )
                        : ATHLTHLocalization.format(
                            english: "Close",
                            norwegian: "Lukk"
                        )
                )

                Spacer()

                if step > 0 {
                    Button {
                        dismiss()
                    } label: {
                        Text(
                            ATHLTHLocalization.format(
                                english: "Cancel",
                                norwegian: "Avbryt"
                            )
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 56, height: 36)
                }
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(
                    ATHLTHLocalization.format(
                        english: "What do you want to achieve?",
                        norwegian: "Hva ønsker du å oppnå?"
                    )
                )
                .font(
                    .system(
                        size: 23,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme.primaryText
                )

                Text(
                    ATHLTHLocalization.format(
                        english: "Choose the goal that fits best. You can fine-tune the target in the next step.",
                        norwegian: "Velg målet som passer best. Du kan finjustere målet i neste steg."
                    )
                )
                .font(
                    .system(
                        size: 13,
                        weight: .regular
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

            ForEach(GoalCategory.allCases) { option in
                let isSelected =
                    category == option

                Button {
                    withAnimation(
                        .snappy(duration: 0.18)
                    ) {
                        category = option
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(
                            systemName:
                                option.systemImage
                        )
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            isSelected
                                ? .white
                                : ATHLTHTheme.accentDeep
                        )
                        .frame(
                            width: 40,
                            height: 40
                        )
                        .background(
                            isSelected
                                ? ATHLTHTheme.accentDeep
                                : ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )

                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(option.title)
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

                            Text(option.subtitle)
                                .font(
                                    .system(
                                        size: 11.5,
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
                                        ? ATHLTHTheme.accentDeep
                                        : Color.secondary.opacity(0.34),
                                    lineWidth: isSelected ? 1.5 : 1.2
                                )
                                .frame(
                                    width: 23,
                                    height: 23
                                )

                            if isSelected {
                                Circle()
                                    .fill(
                                        ATHLTHTheme.accentDeep
                                    )
                                    .frame(
                                        width: 23,
                                        height: 23
                                    )

                                Image(
                                    systemName:
                                        "checkmark"
                                )
                                .font(
                                    .system(
                                        size: 10,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    .white
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        isSelected
                            ? ATHLTHTheme.accentSoft.opacity(0.72)
                            : Color.white.opacity(0.92),
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
                            isSelected
                                ? ATHLTHTheme.accentDeep.opacity(0.34)
                                : Color.black.opacity(0.045),
                            lineWidth: isSelected ? 1.1 : 0.7
                        )
                    }
                    .shadow(
                        color:
                            Color.black.opacity(
                                isSelected ? 0.04 : 0.018
                            ),
                        radius: isSelected ? 10 : 6,
                        y: 3
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var targetStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Define the target")
                .font(.title2.bold())

            TextField("Goal title", text: $title)
                .textFieldStyle(.roundedBorder)

            switch category {
            case .event:
                numberField(title: "Event distance", suffix: "km", value: $targetValue)
                Text("The event itself stays manual. Training-distance milestones can be verified automatically from Apple Health.")
                    .goalHint()

            case .endurance:
                Picker("Activity", selection: $activity) {
                    Text("Running").tag(GoalActivityFilter.running)
                    Text("Walking").tag(GoalActivityFilter.walking)
                    Text("Cycling").tag(GoalActivityFilter.cycling)
                    Text("Hiking").tag(GoalActivityFilter.hiking)
                }
                .pickerStyle(.segmented)

                numberField(title: "Target distance", suffix: "km", value: $targetValue)
                Text("A distance milestone is only completed by a qualifying workout recorded after this goal is created.")
                    .goalHint()

            case .strength:
                TextField("Exercise", text: $exerciseName)
                    .textFieldStyle(.roundedBorder)
                numberField(title: "Target weight", suffix: "kg", value: $targetValue)
                Text("Only sets logged in ATHLTH after goal creation can complete strength milestones.")
                    .goalHint()

            case .body:
                numberField(title: "Target weight", suffix: "kg", value: $targetValue)
                if let current = health.personalDetails.weightKilograms {
                    Text("Current Apple Health weight: \(current, specifier: "%.1f") kg. This becomes the baseline; old weight samples cannot complete new milestones.")
                        .goalHint()
                } else {
                    Text("No Apple Health baseline is available yet. The goal can still be created, but weight milestones will stay manual until a baseline exists.")
                        .goalHint()
                }

            case .consistency:
                numberField(title: "Workout target", suffix: "workouts", value: $targetValue)
                Text("Counts qualifying workouts from the moment this goal is created.")
                    .goalHint()

            case .recovery:
                numberField(title: "Sleep target", suffix: "hours", value: $targetValue)
                Text("Completes when Apple Health records a qualifying sleep after this goal is created.")
                    .goalHint()

            case .custom:
                Text("Custom goals start with manual tracking. You can add and check milestones yourself.")
                    .goalHint()
            }
        }
    }

    private var identityStep: some View {
        let imageButtonTitle = goalImageButtonTitle

        return VStack(alignment: .leading, spacing: 18) {
            Text("Make it yours")
                .font(.title2.bold())

            Toggle("Deadline", isOn: $hasDeadline)
                .disabled(category == .event)

            if hasDeadline || category == .event {
                DatePicker(
                    "Target date",
                    selection: $deadline,
                    in: Calendar.current.startOfDay(for: Date())...,
                    displayedComponents: .date
                )
            }

            Text("Goal image")
                .font(.headline)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(imageButtonTitle)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding()
                .background(
                    Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Picker("Fallback cover", selection: $coverStyle) {
                ForEach(GoalCoverStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }

            TextField("Why this matters (optional)", text: $whyItMatters, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            if let activePlan = session.activePlan {
                Toggle(isOn: $linkActivePlan) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Link training plan")
                        Text(activePlan.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var milestoneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Milestones")
                .font(.title2.bold())

            Text("ATHLTH proposes milestones from your target. You can always check them manually. Automatic rules never use evidence from before the goal was created.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(previewMilestones.enumerated()), id: \.element.id) { index, milestone in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(index == previewMilestones.count - 1 ? ATHLTHTheme.accent : ATHLTHTheme.accent.opacity(0.10))
                            .frame(width: 32, height: 32)
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(index == previewMilestones.count - 1 ? .white : ATHLTHTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(milestone.title)
                            .font(.subheadline.bold())
                        Text(milestone.targetDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let rule = milestone.automationRule {
                            Label(
                                ATHLTHLocalization.format(
                                    english: "Auto · %@ · only new data",
                                    norwegian: "Auto · %@ · bare nye data",
                                    rule.dataSource.title
                                ),
                                systemImage: rule.dataSource.systemImage
                            )
                            .font(.caption2)
                            .foregroundStyle(ATHLTHTheme.accent)
                        } else {
                            Label("Manual", systemImage: "hand.tap.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .goalCard()
            }

            Text("You can add extra manual milestones after creating the goal.")
                .goalHint()
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ready to start")
                .font(.title2.bold())

            GoalPreviewCard(
                title: resolvedTitle,
                category: category,
                deadline: (hasDeadline || category == .event) ? deadline : nil,
                coverStyle: coverStyle,
                imageData: imageData
            )

            Toggle("Make this my Primary Goal", isOn: $makePrimary)

            Picker("Privacy", selection: $privacy) {
                ForEach(GoalPrivacy.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            if linkActivePlan, let activePlan = session.activePlan {
                Label(ATHLTHLocalization.format(
                            english: "Linked to %@",
                            norwegian: "Knyttet til %@",
                            activePlan.title
                        ), systemImage: "list.bullet.clipboard.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Safe automation", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.accent)
                Text("ATHLTH will only auto-complete a milestone when its exact rule is satisfied by the configured source after this goal was created. Manual check and uncheck always remain available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .goalCard()
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

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
                HStack(spacing: 7) {
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
                            size: 14,
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
                            size: 11.5,
                            weight: .bold
                        )
                    )
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(
                    minWidth: 154,
                    minHeight: 44
                )
                .background(
                    canContinue
                        ? ATHLTHTheme.accentDeep
                        : Color.secondary.opacity(0.30),
                    in: Capsule()
                )
                .shadow(
                    color: Color.black.opacity(0.08),
                    radius: 8,
                    y: 3
                )
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)

            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            Color(.systemGroupedBackground)
                .opacity(0.96)
        )
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
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [ATHLTHTheme.accent.opacity(0.88), .black.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(height: 190)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(category.title.uppercased())
                    .font(.caption2.bold())
                    .tracking(1)
                Text(title)
                    .font(.title2.bold())
                if let deadline {
                    Text(deadline.formatted(date: .long, time: .omitted))
                        .font(.caption)
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
