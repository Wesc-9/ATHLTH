import Charts
import Combine
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct ProductRootTabView: View {
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ATHLTHHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            ATHLTHTrainView()
                .tabItem { Label("Train", systemImage: "dumbbell.fill") }
                .tag(1)

            ATHLTHRecoveryView()
                .tabItem { Label("Recovery", systemImage: "leaf.fill") }
                .tag(2)

            ATHLTHProgressView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(3)

            ATHLTHCommunityView()
                .tabItem { Label("Community", systemImage: "person.3.fill") }
                .tag(4)
        }
        .tint(ATHLTHTheme.accent)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .athlthRemoteNotificationTapped
            )
        ) { notification in
            let kind = (
                notification.userInfo?["athlth_kind"] as? String
            )?.lowercased() ?? ""

            if kind.contains("message") ||
                kind.contains("friend") ||
                kind.contains("challenge") ||
                kind.contains("reaction") ||
                kind.contains("workout") {
                selectedTab = 4
            } else {
                selectedTab = 0
            }
        }
        .sheet(
            isPresented: Binding(
                get: {
                    settings.trainingDeviceProvider == .appleWatch &&
                    workoutMirroring.isPresentationRequested
                },
                set: { presented in
                    if !presented &&
                        !workoutMirroring.hasActiveMirroredWorkout {
                        workoutMirroring.dismissSummary()
                    }
                }
            ),
            onDismiss: {
                if !workoutMirroring.hasActiveMirroredWorkout {
                    workoutMirroring.dismissSummary()
                }
            }
        ) {
            MirroredWorkoutLiveView()
                .environmentObject(workoutMirroring)
        }
    }
}

struct ATHLTHHomeView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore

    @State private var homeStreakSnapshot: HealthProgressSnapshot?
    @State private var showingGoalCreation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ZStack(alignment: .topTrailing) {
                        ATHLTHTabHero(
                            imageName: "HomeHero",
                            title: greetingTitle,
                            subtitle: session.profile.presence.state == .training
                                ? "Training now · \(session.profile.presence.workoutTitle ?? "Workout")"
                                : "Your health and training at a glance.",
                            height: 150,
                            alignment: .leading,
                            focalOffsetX: 18
                        )

                        HStack(spacing: 8) {
                            NavigationLink {
                                SocialHubView(initialTab: .messages)
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(
                                        systemName:
                                            homeInboxUnreadCount > 0
                                                ? "tray.full.fill"
                                                : "tray"
                                    )
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(0.38), lineWidth: 1)
                                    }

                                    if homeInboxUnreadCount > 0 {
                                        Text(homeInboxBadgeText)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(minWidth: 14, minHeight: 14)
                                            .padding(.horizontal, homeInboxUnreadCount > 9 ? 2 : 0)
                                            .background(.red, in: Capsule())
                                            .overlay {
                                                Capsule()
                                                    .stroke(.white, lineWidth: 1)
                                            }
                                            .offset(x: 4, y: -4)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                homeInboxUnreadCount > 0
                                    ? "Inbox, \(homeInboxUnreadCount) unread"
                                    : "Inbox"
                            )

                            NavigationLink {
                                ATHLTHNotificationCenterView()
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(
                                        systemName:
                                            notifications.unreadCount > 0
                                                ? "bell.fill"
                                                : "bell"
                                    )
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(0.38), lineWidth: 1)
                                    }

                                    if notifications.unreadCount > 0 {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 9, height: 9)
                                            .overlay {
                                                Circle().stroke(.white, lineWidth: 1.5)
                                            }
                                            .offset(x: 1, y: -1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                notifications.unreadCount > 0
                                    ? "Notifications, \(notifications.unreadCount) unread"
                                    : "Notifications"
                            )

                            NavigationLink {
                                ATHLTHProfileView()
                            } label: {
                                homeProfileShortcut
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Profile")
                        }
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                    }

                    ATHLTHCard {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Your Day")
                                    .font(.title3.weight(.bold))
                                Text(homeHealthSourceText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if health.isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            } else if let refreshed = health.lastSuccessfulRefreshAt {
                                Text(refreshed, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        HStack(alignment: .top, spacing: 10) {
                            HomeDayStatus(
                                title: "Move",
                                value: moveValue,
                                subtitle: moveSubtitle,
                                icon: "flame.fill",
                                progress: moveProgress
                            )

                            HomeDayStatus(
                                title: "Recovery",
                                value: recoveryValue,
                                subtitle: health.recovery.state.title,
                                icon: health.recovery.state.systemImage,
                                progress: health.recovery.score.map {
                                    Double($0) / 100
                                }
                            )

                            HomeDayStatus(
                                title: "Sleep",
                                value: sleepValue,
                                subtitle: sleepSubtitle,
                                icon: "moon.fill",
                                progress: health.sleep.totalAsleep > 0
                                    ? min(health.sleep.totalAsleep / (8 * 3_600), 1)
                                    : nil
                            )
                        }
                        .padding(.top, 14)
                    }

                    HomeCurrentStreakCard(snapshot: homeStreakSnapshot)

                    homeGoalsCard

                    HomeActivitySection()

                    if let insight = homeInsight {
                        ATHLTHCard {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: insight.icon)
                                    .font(.title2)
                                    .foregroundStyle(ATHLTHTheme.accent)
                                    .frame(width: 46, height: 46)
                                    .background(
                                        ATHLTHTheme.accentSoft,
                                        in: RoundedRectangle(
                                            cornerRadius: 14,
                                            style: .continuous
                                        )
                                    )

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("For You")
                                        .font(.caption.weight(.semibold))
                                        .tracking(1.4)
                                        .foregroundStyle(ATHLTHTheme.mutedText)

                                    Text(insight.title)
                                        .font(.headline)

                                    Text(insight.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(
                                            horizontal: false,
                                            vertical: true
                                        )
                                }

                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [
                        .blue.opacity(0.055),
                        ATHLTHTheme.accent.opacity(0.035),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .refreshable {
                async let healthRefresh: Void = health.refreshAll()
                async let streakRefresh: Void = loadHomeStreak()
                async let goalsRefresh: Void = goalStore.refreshAutomaticMilestones(
                    health: health,
                    strength: strengthWorkout
                )
                _ = await (healthRefresh, streakRefresh, goalsRefresh)
            }
            .task {
                if health.lastSuccessfulRefreshAt == nil {
                    await health.refreshAll()
                }
                await loadHomeStreak()
                await goalStore.refreshAutomaticMilestones(
                    health: health,
                    strength: strengthWorkout
                )
            }
        }
        .sheet(isPresented: $showingGoalCreation) {
            GoalCreationView()
        }
    }

    @MainActor
    private func loadHomeStreak() async {
        guard health.healthDataAvailable, health.hasRequestedAuthorization else {
            homeStreakSnapshot = nil
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -90, to: today)
            ?? now.addingTimeInterval(-7_776_000)
        let previousStart = calendar.date(byAdding: .day, value: -90, to: start)
            ?? start.addingTimeInterval(-7_776_000)

        homeStreakSnapshot = try? await health.progressSnapshot(
            startDate: start,
            endDate: now,
            previousStartDate: previousStart,
            previousEndDate: start,
            grouping: .day
        )
    }

    private var homeInboxUnreadCount: Int {
        messaging.unreadCount + messaging.messageRequestCount
    }

    private var homeInboxBadgeText: String {
        homeInboxUnreadCount > 99 ? "99+" : "\(homeInboxUnreadCount)"
    }

    @ViewBuilder
    private var homeProfileShortcut: some View {
        if let avatarURL = session.profile.avatarURL {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.48), lineWidth: 1)
            }
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.48), lineWidth: 1)
                }
        }
    }

    private var homeHealthSourceText: String {
        if !health.hasRequestedAuthorization {
            switch settings.trainingDeviceProvider {
            case .garmin:
                return "Garmin sync pending"
            case .appleWatch, .none:
                return "No health source connected"
            }
        }

        switch settings.trainingDeviceProvider {
        case .appleWatch:
            return "Apple Health + Apple Watch"
        case .garmin:
            return "Apple Health · Garmin sync pending"
        case .none:
            return "Apple Health / iPhone"
        }
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String

        switch hour {
        case 5..<12:
            greeting = "Good morning"
        case 12..<18:
            greeting = "Good afternoon"
        default:
            greeting = "Good evening"
        }

        return "\(greeting), \(session.profile.displayName)"
    }

    private var moveValue: String {
        guard let calories = health.training.activeEnergyKilocaloriesToday,
              calories > 0
        else {
            return "—"
        }

        return "\(Int(calories.rounded())) kcal"
    }

    private var moveProgress: Double? {
        guard let calories = health.training.activeEnergyKilocaloriesToday,
              let goal = health.training.moveGoalKilocaloriesToday,
              goal > 0
        else {
            return nil
        }

        return min(max(calories / goal, 0), 1)
    }

    private var moveSubtitle: String {
        guard let calories = health.training.activeEnergyKilocaloriesToday
        else {
            return "No data yet"
        }

        if let goal = health.training.moveGoalKilocaloriesToday,
           goal > 0 {
            let percent = Int(
                ((calories / goal) * 100).rounded()
            )
            return "\(percent)% of goal"
        }

        if let minutes = health.training.exerciseMinutesToday,
           minutes > 0 {
            return "\(Int(minutes.rounded())) exercise min"
        }

        return "Today"
    }

    private var recoveryValue: String {
        guard let score = health.recovery.score else {
            return "—"
        }

        return "\(score)"
    }

    private var sleepValue: String {
        guard health.sleep.totalAsleep > 0 else {
            return "—"
        }

        return health.sleep.totalAsleep.shortDuration
    }

    private var sleepSubtitle: String {
        guard health.sleep.totalAsleep > 0 else {
            return "No sleep data"
        }

        if let baseline = health.recovery.averageSleepDuration,
           baseline > 0 {
            let difference = health.sleep.totalAsleep - baseline
            let minutes = Int(abs(difference / 60).rounded())

            if minutes < 10 {
                return "Near your baseline"
            }

            return difference >= 0
                ? "+\(minutes)m vs baseline"
                : "−\(minutes)m vs baseline"
        }

        if health.sleep.totalAsleep >= 7.5 * 3_600 {
            return "Good duration"
        }

        if health.sleep.totalAsleep >= 6.5 * 3_600 {
            return "A little short"
        }

        return "Short night"
    }

    private var homeGoalsCard: some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goals")
                        .font(.title3.weight(.bold))
                    Text("Keep your biggest targets visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    GoalsHubView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                Button {
                    showingGoalCreation = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(ATHLTHTheme.accentSoft, in: Circle())
                }
                .buttonStyle(.plain)
            }

            if let primary = goalStore.primaryGoal {
                Text("PRIMARY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                NavigationLink {
                    GoalDetailView(goalID: primary.id)
                } label: {
                    homeGoalRow(primary)
                }
                .buttonStyle(.plain)

                let secondary = goalStore.activeGoals
                    .filter { !$0.isPrimary }
                    .prefix(2)

                ForEach(Array(secondary)) { goal in
                    Divider().overlay(Color.black.opacity(0.05))

                    NavigationLink {
                        GoalDetailView(goalID: goal.id)
                    } label: {
                        homeGoalRow(goal)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text("Create your first goal")
                        .font(.subheadline.weight(.semibold))

                    Text("Set a target and milestones, then keep progress visible from Home.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Add Goal") {
                        showingGoalCreation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }

    private func homeGoalRow(_ goal: ATHLTHGoal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: goal.category.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 38, height: 38)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(goal.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int((goal.progress * 100).rounded()))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.accent)
                }

                HStack {
                    Text(homeGoalDeadlineText(goal))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(goal.completedMilestones)/\(goal.milestones.count) milestones")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.055))
                        Capsule()
                            .fill(ATHLTHTheme.accent)
                            .frame(width: proxy.size.width * goal.progress)
                    }
                }
                .frame(height: 6)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func homeGoalDeadlineText(_ goal: ATHLTHGoal) -> String {
        guard let deadline = goal.deadline else {
            return goal.dataSource.title
        }

        if deadline < Date() {
            return "Deadline passed"
        }

        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: deadline)
        ).day ?? 0

        if days == 0 { return "Today" }
        if days == 1 { return "1 day left" }
        return "\(days) days left"
    }

    private var homeInsight: (
        title: String,
        detail: String,
        icon: String
    )? {
        if let score = health.recovery.score {
            switch health.recovery.state {
            case .ready:
                return (
                    "You look ready for a normal training load.",
                    health.recovery.detail,
                    "bolt.heart.fill"
                )
            case .balanced:
                return (
                    "Recovery looks balanced today.",
                    health.recovery.detail,
                    "heart.fill"
                )
            case .takeItEasy:
                return (
                    "A lighter session may fit better today.",
                    health.recovery.detail,
                    "gauge.with.dots.needle.33percent"
                )
            case .recover:
                return (
                    "Recovery signals are below your baseline.",
                    "Consider reducing intensity and prioritizing sleep and recovery today.",
                    "bed.double.fill"
                )
            case .buildingBaseline:
                break
            }

            if score >= 0 {
                return nil
            }
        }

        if health.recovery.state == .buildingBaseline {
            return (
                "ATHLTH is building your recovery baseline.",
                health.recovery.detail,
                "waveform.path.ecg"
            )
        }

        return nil
    }
}

private struct HomeDayStatus: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 30, height: 30)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.72)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

            if let progress {
                ProgressView(value: progress)
                    .tint(ATHLTHTheme.accent)
            } else {
                Capsule()
                    .fill(ATHLTHTheme.border)
                    .frame(height: 4)
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            minHeight: 150,
            alignment: .topLeading
        )
        .background(
            Color.white.opacity(0.72),
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
            .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
    }
}

private struct HomeCurrentStreakCard: View {
    let snapshot: HealthProgressSnapshot?

    private var currentWeekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? calendar.startOfDay(for: Date())

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private func isWorkoutDay(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        return snapshot?.activeWorkoutDays.contains {
            calendar.isDate($0, inSameDayAs: day)
        } ?? false
    }

    private var workoutStreak: Int {
        guard let days = snapshot?.activeWorkoutDays, !days.isEmpty else {
            return 0
        }

        let calendar = Calendar.current
        let active = Set(days.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: Date())

        var cursor: Date
        if active.contains(today) {
            cursor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  active.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while active.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }

        return streak
    }

    private var activeDaysThisWeek: Int {
        currentWeekDays.filter(isWorkoutDay).count
    }

    var body: some View {
        ATHLTHCard {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        workoutStreak > 0
                            ? ATHLTHTheme.accent
                            : Color.secondary.opacity(0.45)
                    )
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Streak")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(
                        workoutStreak > 0
                            ? "\(workoutStreak) day\(workoutStreak == 1 ? "" : "s")"
                            : "Start your streak"
                    )
                    .font(.title3.weight(.bold))

                    Text(
                        workoutStreak > 0
                            ? "Keep it going."
                            : "Complete a workout to begin."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(currentWeekDays, id: \.self) { day in
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(
                                    isWorkoutDay(day)
                                        ? ATHLTHTheme.accent
                                        : Color.black.opacity(0.055)
                                )
                                .frame(width: 26, height: 26)

                            if isWorkoutDay(day) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }

                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 12)

            Text(
                "\(activeDaysThisWeek) active \(activeDaysThisWeek == 1 ? "day" : "days") this week"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }
}

struct ATHLTHTrainView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var spotifyPlayback: SpotifyPlaybackStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningWorkoutLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var social: SocialStore

    @State private var selectedSection = 0
    @State private var showingFileImporter = false
    @State private var importMessage: String?
    @State private var importError: String?
    @State private var watchTransferMessage: String?
    @State private var watchTransferError: String?
    @State private var selectedStrengthSession: PlannedSession?
    @State private var pendingQuickStartKind: WorkoutKind?
    @State private var showingStrengthWorkout = false

    private var gpxImporter: GPXRouteImporter {
        GPXRouteImporter(ownerID: session.profile.userID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHTabHero(
                        imageName: "TrainHero",
                        title: "Train",
                        subtitle: "Build a stronger, healthier you.",
                        height: 150,
                        alignment: .leading,
                        focalOffsetX: 20
                    )

                    Picker("Training section", selection: $selectedSection) {
                        Text("Today").tag(0)
                        Text("Calendar").tag(1)
                        Text("Programs").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch selectedSection {
                    case 1:
                        ATHLTHPlusFeatureGate(
                            feature: .advancedTrainingPlans,
                            title: "Training Calendar",
                            message: "Schedule and adjust the active program across days and weeks with ATHLTH+."
                        ) {
                            AdvancedPlannerView {
                                selectedSection = 2
                            }
                        }
                    case 2:
                        TrainingPlanManagerView {
                            selectedSection = 1
                        }
                    default:
                        todayContent
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .sheet(item: $selectedStrengthSession) { workout in
                WorkoutStartOptionsView(
                    session: workout,
                    trainingDeviceProvider: settings.trainingDeviceProvider,
                    watchConnected:
                        settings.trainingDeviceProvider == .appleWatch &&
                        watchConnection.isReady,
                    defaultCapture: settings.preferredWorkoutCapture,
                    defaultTracking: settings.defaultStrengthTracking,
                    linkedSpotifyPlaylist: session.activePlan?.spotifyPlaylist,
                    spotifyAutoplayEnabled:
                        settings.spotifyAutoplayLinkedPlaylists &&
                        (session.activePlan?.spotifyAutoplayOnWorkoutStart ?? false)
                ) { captureDevice, trackingMode, selectedFriends in
                    Task { @MainActor in
                        await social.beginWorkoutWithFriends(
                            title: workout.title,
                            kind: .strength,
                            friends: selectedFriends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username
                        )

                        if captureDevice == .appleWatch {
                            do {
                                try await watchConnection.startWorkoutOnWatch(.strength)
                                startPlanSpotifyIfNeeded()
                                session.beginTrainingStatus(for: workout)
                                strengthWorkout.start(
                                    session: workout,
                                    watchSessionID: UUID(),
                                    trackingMode: trackingMode,
                                    captureDevice: .appleWatch
                                )
                                showingStrengthWorkout = true
                            } catch {
                                watchTransferError = error.localizedDescription
                            }
                        } else {
                            startPlanSpotifyIfNeeded()
                            session.beginTrainingStatus(for: workout)
                            strengthWorkout.start(
                                session: workout,
                                watchSessionID: nil,
                                trackingMode: trackingMode,
                                captureDevice: .iPhone
                            )
                            showingStrengthWorkout = true
                        }
                    }
                }
            }
            .sheet(item: $pendingQuickStartKind) { kind in
                QuickWorkoutStartSheet(
                    kind: kind,
                    trainingDeviceProvider: settings.trainingDeviceProvider,
                    watchConnected:
                        settings.trainingDeviceProvider == .appleWatch &&
                        watchConnection.isReady
                ) { selectedFriends in
                    Task { @MainActor in
                        await social.beginWorkoutWithFriends(
                            title: kind.title,
                            kind: kind,
                            friends: selectedFriends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username
                        )
                        startQuickWorkoutOnWatch(kind)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingStrengthWorkout) {
                ActiveStrengthWorkoutView()
                    .environmentObject(strengthWorkout)
                    .environmentObject(session)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.xml, .data],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await importGPX(result)
                }
            }
            .task {
                await exerciseLibrary.refresh()
            }
            .alert("ATHLTH", isPresented: Binding(
                get: {
                    importMessage != nil ||
                    importError != nil ||
                    watchTransferMessage != nil ||
                    watchTransferError != nil
                },
                set: { newValue in
                    if !newValue {
                        importMessage = nil
                        importError = nil
                        watchTransferMessage = nil
                        watchTransferError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    importMessage = nil
                    importError = nil
                    watchTransferMessage = nil
                    watchTransferError = nil
                }
            } message: {
                Text(
                    watchTransferError ??
                    importError ??
                    watchTransferMessage ??
                    importMessage ??
                    ""
                )
            }
        }
    }

    @ViewBuilder
    private var todayContent: some View {
        if let plan = session.activePlan {
            ATHLTHCard {
                ATHLTHSectionHeader(
                    title: "Today's Program",
                    actionTitle: plan.title
                )

                let sessions = todaySessions(in: plan)

                if sessions.isEmpty {
                    Label(
                        "No session planned today",
                        systemImage: "leaf"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                } else {
                    VStack(spacing: 14) {
                        ForEach(sessions) { workout in
                            HStack {
                                Image(systemName: workout.kind.systemImage)
                                    .foregroundStyle(ATHLTHTheme.accent)
                                    .frame(width: 34)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.title)
                                        .font(.headline)

                                    Text(todaySessionSummary(workout))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if workout.kind == .strength {
                                    Button("Start") {
                                        selectedStrengthSession = workout
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }

        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Quick Start",
                actionTitle: quickStartDeviceTitle
            )
            HStack {
                ForEach([WorkoutKind.running, .walking, .strength]) { kind in
                    Button {
                        handleQuickStart(kind)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: kind.systemImage)
                                .font(.title2)
                                .foregroundStyle(ATHLTHTheme.accent)
                            Text(kind.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                    }
                    .buttonStyle(.plain)
                    .disabled(!quickStartAvailable(kind))
                    .opacity(quickStartAvailable(kind) ? 1 : 0.45)
                }
            }
            .padding(.top, 10)
        }

        if !session.savedWorkoutTemplates.isEmpty {
            ATHLTHCard {
                ATHLTHSectionHeader(
                    title: "Saved Workouts",
                    actionTitle: "From you & friends"
                )

                VStack(spacing: 13) {
                    ForEach(session.savedWorkoutTemplates.prefix(4)) { workout in
                        HStack(spacing: 12) {
                            Image(systemName: workout.kind.systemImage)
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(width: 36, height: 36)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 11)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(todaySessionSummary(workout))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if workout.kind == .strength {
                                Button("Start") {
                                    selectedStrengthSession = workout
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Text("Saved")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }
        }

        ATHLTHCard {
            HStack(spacing: 10) {
                Text("Routes")
                    .font(.title3.weight(.semibold))

                Spacer()

                NavigationLink {
                    SavedRoutesView()
                } label: {
                    Text("See All")
                        .font(.caption.weight(.semibold))
                }

                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)

                Button {
                    showingFileImporter = true
                } label: {
                    Label("GPX", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }

            if let route = session.savedRoutes.first {
                Map(initialPosition: .region(routeRegion(route))) {
                    MapPolyline(coordinates: route.coordinates.map(\.coordinate))
                        .stroke(ATHLTHTheme.accent, lineWidth: 5)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.top, 10)

                HStack {
                    VStack(alignment: .leading) {
                        Text(route.title)
                            .font(.headline)
                        Text("\(route.distanceKilometers, specifier: "%.1f") km · \(Int(route.elevationGainMeters ?? 0)) m ascent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.top, 8)

                routeDeviceActions(route)
                    .padding(.top, 8)
            } else {
                ContentUnavailableView(
                    "No routes yet",
                    systemImage: "map",
                    description: Text("Create an A-to-B running route or import GPX.")
                )
                .frame(height: 190)
            }
        }

        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Workout Builder",
                actionTitle: "Library"
            )

            HStack(spacing: 10) {
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    builderTile(
                        title: "Exercises",
                        subtitle: exerciseLibrary.repDBExercises.isEmpty
                            ? "RepDB + Custom"
                            : "\(exerciseLibrary.repDBExercises.count) + custom",
                        icon: "dumbbell.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RunningWorkoutLibraryView()
                } label: {
                    builderTile(
                        title: "Running",
                        subtitle: "\(runningWorkoutLibrary.allTemplates.count) workouts",
                        icon: "figure.run"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }


    }

    private func watchWorkoutKind(
        for kind: WorkoutKind
    ) -> WatchWorkoutKind? {
        switch kind {
        case .running:
            return .running
        case .walking:
            return .walking
        case .strength:
            return .strength
        case .mobility, .recovery, .custom:
            return nil
        }
    }

    private func quickStartAvailable(_ kind: WorkoutKind) -> Bool {
        if kind == .strength {
            return strengthWorkout.activeWorkout == nil
        }

        guard watchWorkoutKind(for: kind) != nil else {
            return false
        }

        if settings.trainingDeviceProvider == .appleWatch {
            return !watchConnection.workoutLaunchInProgress
        }

        return true
    }

    private func handleQuickStart(_ kind: WorkoutKind) {
        if kind == .strength {
            selectedStrengthSession = PlannedSession(
                id: UUID(),
                title: "Freestyle Strength",
                kind: .strength,
                scheduledStart: nil,
                durationMinutes: nil,
                targetDistanceKilometers: nil,
                targetPaceSecondsPerKilometer: nil,
                routeID: nil,
                exercises: [],
                notes: "Freestyle gym session",
                runningWorkout: nil
            )
            return
        }

        pendingQuickStartKind = kind
    }

    private var quickStartDeviceTitle: String {
        switch settings.trainingDeviceProvider {
        case .appleWatch:
            return watchConnection.isReady ? "Apple Watch" : "Apple Watch setup"
        case .garmin:
            return "Garmin · sync pending"
        case .none:
            return "No watch"
        }
    }

    @ViewBuilder
    private func routeDeviceActions(
        _ route: TrainingRoute
    ) -> some View {
        switch settings.trainingDeviceProvider {
        case .appleWatch:
            HStack(spacing: 10) {
                Button {
                    sendRouteToWatch(route)
                } label: {
                    Label("Send to Apple Watch", systemImage: "applewatch")
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHTheme.accent)
                .disabled(!watchConnection.isReady)

                if !watchConnection.isReady {
                    Text(watchConnection.state.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

        case .garmin:
            HStack(spacing: 10) {
                Label("Garmin route sync", systemImage: "watch.analog")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)

                Text("Planned · authorization pending")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .none:
            Label(
                "Route stays available on iPhone",
                systemImage: "iphone"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func startQuickWorkoutOnWatch(_ kind: WorkoutKind) {
        guard settings.trainingDeviceProvider == .appleWatch,
              watchConnection.isReady,
              let watchKind = watchWorkoutKind(for: kind)
        else {
            return
        }

        Task {
            do {
                try await watchConnection.startWorkoutOnWatch(watchKind)
                watchTransferMessage = "\(watchKind.title) started on Apple Watch."
            } catch {
                watchTransferError = error.localizedDescription
            }
        }
    }

    private func sendRouteToWatch(_ route: TrainingRoute) {
        guard settings.trainingDeviceProvider == .appleWatch,
              watchConnection.isReady
        else {
            return
        }

        do {
            try watchConnection.sendRoute(route)
            watchTransferMessage = "Sent \(route.title) to Apple Watch."
        } catch {
            watchTransferError = error.localizedDescription
        }
    }

    private func startPlanSpotifyIfNeeded() {
        guard
            let plan = session.activePlan,
            plan.spotifyAutoplayOnWorkoutStart,
            let playlist = plan.spotifyPlaylist
        else {
            return
        }

        Task {
            await spotifyPlayback.startLinkedPlaylist(
                playlist,
                settings: settings
            )
        }
    }

    private func todaySessions(
        in plan: TrainingPlan
    ) -> [PlannedSession] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let dayIndex = ((weekday + 5) % 7) + 1

        let week: TrainingPlanWeek?
        if let startDate = plan.startDate {
            let start = calendar.startOfDay(for: startDate)
            let today = calendar.startOfDay(for: Date())
            let days = max(
                calendar.dateComponents(
                    [.day],
                    from: start,
                    to: today
                ).day ?? 0,
                0
            )
            let weekIndex = min(
                days / 7,
                max(plan.weeks.count - 1, 0)
            )
            week = plan.weeks.indices.contains(weekIndex)
                ? plan.weeks[weekIndex]
                : plan.weeks.first
        } else {
            week = plan.weeks.first
        }

        return week?
            .days
            .first(where: { $0.dayIndex == dayIndex })?
            .sessions ?? []
    }

    private func todaySessionSummary(
        _ workout: PlannedSession
    ) -> String {
        var parts: [String] = []

        if let running = workout.runningWorkout {
            parts.append(running.type.title)
            parts.append("\(running.blocks.count) blocks")
        } else if let duration = workout.durationMinutes {
            parts.append("\(duration) min")
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

    @ViewBuilder
    private func builderTile(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(ATHLTHTheme.accent)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            minHeight: 100,
            alignment: .leading
        )
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func routeRegion(_ route: TrainingRoute) -> MKCoordinateRegion {
        guard let first = route.coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 66.3126, longitude: 14.1428),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            )
        }

        return MKCoordinateRegion(
            center: first.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    }

    private func importGPX(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let route = try await gpxImporter.importGPX(data: data, filename: url.lastPathComponent)

            await MainActor.run {
                session.addImportedRoute(route)
                importMessage = "Imported \(route.title) · \(String(format: "%.1f", route.distanceKilometers)) km"
            }
        } catch {
            await MainActor.run {
                importError = error.localizedDescription
            }
        }
    }
}

struct ATHLTHRecoveryView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ATHLTHTabHero(
                        imageName: "RecoveryHero",
                        title: "Recovery",
                        subtitle: "Use sleep and recovery signals to guide today's load.",
                        height: 146,
                        alignment: .leading,
                        focalOffsetX: 14
                    )

                    ATHLTHPlusFeatureGate(
                        feature: .advancedRecovery,
                        title: "Advanced Recovery",
                        message: "Recovery scoring, trends and training guidance are included with ATHLTH+."
                    ) {
                        VStack(spacing: 18) {
                            ATHLTHCard {
                                ATHLTHSectionHeader(
                                    title: "Recovery",
                                    actionTitle: "Today"
                                )

                                if let score = health.recovery.score {
                                    HStack(spacing: 24) {
                                        ATHLTHProgressRing(
                                            title: health.recovery.state.title,
                                            value: "\(score)",
                                            progress: Double(score) / 100,
                                            icon: health.recovery.state.systemImage,
                                            tint: ATHLTHTheme.accent
                                        )

                                        VStack(
                                            alignment: .leading,
                                            spacing: 8
                                        ) {
                                            Text(recoveryHeadline)
                                                .font(.title2.weight(.bold))

                                            Text(health.recovery.detail)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.top, 12)
                                } else {
                                    HStack(spacing: 16) {
                                        Image(
                                            systemName:
                                                "waveform.path.ecg"
                                        )
                                        .font(.title2)
                                        .foregroundStyle(
                                            ATHLTHTheme.accent
                                        )
                                        .frame(width: 54, height: 54)
                                        .background(
                                            ATHLTHTheme.accentSoft,
                                            in: RoundedRectangle(
                                                cornerRadius: 16,
                                                style: .continuous
                                            )
                                        )

                                        VStack(
                                            alignment: .leading,
                                            spacing: 5
                                        ) {
                                            Text("Building your baseline")
                                                .font(.headline)

                                            Text(health.recovery.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(.top, 12)
                                }
                            }

                            HStack(spacing: 12) {
                                ATHLTHCard {
                                    ATHLTHSectionHeader(title: "Sleep")
                                    ATHLTHMetric(
                                        title: "Last sleep",
                                        value: health.sleep.totalAsleep > 0
                                            ? health.sleep.totalAsleep.shortDuration
                                            : "—",
                                        icon: "moon.fill",
                                        tint: .purple
                                    )
                                    .padding(.top, 10)
                                }

                                ATHLTHCard {
                                    ATHLTHSectionHeader(
                                        title: "Heart & HRV"
                                    )
                                    HStack {
                                        ATHLTHMetric(
                                            title: "HRV",
                                            value:
                                                health.heart.hrvMilliseconds
                                                .map {
                                                    "\(Int($0.rounded())) ms"
                                                } ?? "—",
                                            icon: "waveform.path.ecg",
                                            tint: .blue
                                        )

                                        ATHLTHMetric(
                                            title: "Resting HR",
                                            value:
                                                health.heart.restingHeartRate
                                                .map {
                                                    "\(Int($0.rounded())) bpm"
                                                } ?? "—",
                                            icon: "heart.fill",
                                            tint: .red
                                        )
                                    }
                                    .padding(.top, 10)
                                }
                            }

                            ATHLTHCard {
                                ATHLTHSectionHeader(
                                    title: "Baseline",
                                    actionTitle:
                                        health.recovery.baselineDays > 0
                                        ? "\(health.recovery.baselineDays) days"
                                        : nil
                                )

                                HStack(spacing: 18) {
                                    baselineMetric(
                                        title: "Sleep",
                                        value:
                                            health.recovery
                                            .averageSleepDuration
                                            .map(\.shortDuration) ?? "—"
                                    )

                                    baselineMetric(
                                        title: "HRV",
                                        value:
                                            health.recovery
                                            .baselineHRVMilliseconds
                                            .map {
                                                "\(Int($0.rounded())) ms"
                                            } ?? "—"
                                    )

                                    baselineMetric(
                                        title: "Resting HR",
                                        value:
                                            health.recovery
                                            .baselineRestingHeartRate
                                            .map {
                                                "\(Int($0.rounded())) bpm"
                                            } ?? "—"
                                    )
                                }
                                .padding(.top, 12)

                                Text(
                                    "ATHLTH uses recent sleep, HRV and resting heart rate to compare today with your own baseline."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 10)
                            }

                            ATHLTHCard {
                                ATHLTHSectionHeader(
                                    title: "Today's Guidance"
                                )

                                Label(
                                    guidanceTitle,
                                    systemImage: health.recovery.state.systemImage
                                )
                                .font(.headline)
                                .foregroundStyle(ATHLTHTheme.accent)
                                .padding(.top, 10)

                                Text(guidanceDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                await health.refreshAll()
            }
        }
    }

    private var recoveryHeadline: String {
        switch health.recovery.state {
        case .ready:
            return "Well recovered"
        case .balanced:
            return "Balanced recovery"
        case .takeItEasy:
            return "A lighter day may fit"
        case .recover:
            return "Prioritize recovery"
        case .buildingBaseline:
            return "Building your baseline"
        }
    }

    private var guidanceTitle: String {
        switch health.recovery.state {
        case .ready:
            return "Normal training load"
        case .balanced:
            return "Train as planned"
        case .takeItEasy:
            return "Consider lower intensity"
        case .recover:
            return "Recovery first"
        case .buildingBaseline:
            switch settings.trainingDeviceProvider {
            case .appleWatch:
                return "Keep wearing your Apple Watch"
            case .garmin:
                return "Garmin sync is waiting for authorization"
            case .none:
                return "More health data is needed"
            }
        }
    }

    private var guidanceDetail: String {
        switch health.recovery.state {
        case .ready:
            return "Your current recovery signals support a normal session today."
        case .balanced:
            return "Your signals are close to baseline. Follow the plan and adjust if effort feels unusually high."
        case .takeItEasy:
            return "Sleep, HRV or resting heart rate are below your recent pattern. Consider reducing intensity or volume."
        case .recover:
            return "Your combined recovery signals are well below baseline. A rest day, mobility or easy activity may be more appropriate."
        case .buildingBaseline:
            switch settings.trainingDeviceProvider {
            case .appleWatch:
                return "ATHLTH needs at least five usable days with sleep, HRV and resting heart-rate data before showing a recovery score."
            case .garmin:
                return "The recovery model is ready for Garmin sleep, HRV and resting heart-rate data. Until Garmin authorization is approved, ATHLTH uses any compatible data already available through Apple Health."
            case .none:
                return "Recovery scoring needs sleep, HRV and resting heart-rate data. Without a wearable, ATHLTH leaves the score unavailable instead of estimating or failing."
            }
        }
    }

    @ViewBuilder
    private func baselineMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ProgressPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"
    case year = "Year"

    var id: String { rawValue }
}

struct ATHLTHProgressView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var trophyStore: TrophyStore

    @State private var period: ProgressPeriod = .week
    @State private var progressSnapshot: HealthProgressSnapshot?
    @State private var monthlySnapshot: HealthProgressSnapshot?
    @State private var consistencySnapshot: HealthProgressSnapshot?
    @State private var personalRecords: [HealthPersonalRecord] = []
    @State private var progressLoading = false
    @State private var progressError: String?

    private let green = ATHLTHTheme.accent
    private let blue = Color(red: 0.20, green: 0.56, blue: 0.96)
    private let purple = Color(red: 0.42, green: 0.36, blue: 0.95)
    private let canvas = Color(red: 0.965, green: 0.972, blue: 0.968)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ATHLTHTabHero(
                        imageName: "ProgressHero",
                        title: "Progress",
                        subtitle: "See your training, consistency and health trends.",
                        height: 150,
                        alignment: .leading,
                        focalOffsetX: 18
                    )

                    periodPicker

                    weeklyOverview

                    HStack(alignment: .top, spacing: 12) {
                        workoutsCompletedCard
                        dailyStepsCard
                    }

                    HStack(alignment: .top, spacing: 12) {
                        consistencyCard
                        personalRecordsCard
                    }

                    HStack(alignment: .top, spacing: 12) {
                        monthlyStatsCard
                        achievementsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(canvas.ignoresSafeArea())
            .refreshable {
                async let selected: Void = loadProgressData()
                async let support: Void = loadSupportingProgressData()
                _ = await (selected, support)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: period) {
            await loadProgressData()
        }
        .task {
            await loadSupportingProgressData()
            await goalStore.refreshAutomaticMilestones(
                health: health,
                strength: strengthWorkout
            )
            await trophyStore.refresh(
                health: health,
                strength: strengthWorkout,
                goals: goalStore
            )
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProgressPeriod.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        period = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(period == option ? .semibold : .medium))
                        .foregroundStyle(period == option ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            period == option ? green : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white.opacity(0.96), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(overviewTitle)
                    .font(.title3.weight(.bold))

                Spacer()

                Text(periodDateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                overviewMetric(
                    icon: "dumbbell.fill",
                    tint: green,
                    value: progressSnapshot.map { String($0.workoutCount) } ?? "—",
                    title: "Workouts",
                    change: progressSnapshot?.workoutChangePercent,
                    footer: comparisonLabel
                )

                overviewDivider

                overviewMetric(
                    icon: "shoeprints.fill",
                    tint: blue,
                    value: formattedSteps(progressSnapshot?.averageDailySteps),
                    title: "Steps/Day",
                    change: progressSnapshot?.stepsChangePercent,
                    footer: comparisonLabel
                )

                overviewDivider

                overviewMetric(
                    icon: "moon.fill",
                    tint: purple,
                    value: progressSnapshot?.averageSleepDuration.map { $0.shortDuration } ?? "—",
                    title: "Sleep/Day",
                    change: progressSnapshot?.sleepChangePercent,
                    footer: comparisonLabel
                )

                overviewDivider

                overviewMetric(
                    icon: "leaf.fill",
                    tint: green,
                    value: "Soon",
                    title: "Recovery",
                    change: nil,
                    footer: "ATHLTH score"
                )
            }

            if progressLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else if let progressError {
                Label(progressError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private var workoutsCompletedCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            compactHeader("Workouts Completed")

            HStack(alignment: .top, spacing: 10) {
                if let snapshot = progressSnapshot, !snapshot.buckets.isEmpty {
                    Chart(snapshot.buckets) { bucket in
                        BarMark(
                            x: .value("Period", bucketAxisLabel(bucket.startDate)),
                            y: .value("Workouts", bucket.workoutCount)
                        )
                        .foregroundStyle(green.gradient)
                        .cornerRadius(4)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine().foregroundStyle(Color.black.opacity(0.045))
                            AxisValueLabel().font(.system(size: 8))
                        }
                    }
                    .chartXAxis {
                        AxisMarks {
                            AxisValueLabel().font(.system(size: 8))
                        }
                    }
                    .frame(height: 120)
                } else {
                    chartPlaceholder(icon: "figure.run")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(progressSnapshot.map { String($0.workoutCount) } ?? "—")
                        .font(.title2.weight(.bold))
                    Text(periodSummaryLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    changeIndicator(progressSnapshot?.workoutChangePercent)
                        .padding(.top, 7)

                    Text(comparisonLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 66, alignment: .leading)
            }
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var dailyStepsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            compactHeader("Daily Steps")

            HStack(alignment: .top, spacing: 10) {
                if let snapshot = progressSnapshot, !snapshot.buckets.isEmpty {
                    Chart(snapshot.buckets) { bucket in
                        BarMark(
                            x: .value("Period", bucketAxisLabel(bucket.startDate)),
                            y: .value("Steps", bucket.averageDailySteps ?? 0)
                        )
                        .foregroundStyle(blue.gradient)
                        .cornerRadius(4)
                    }
                    .chartYScale(domain: 0...stepsChartUpperBound)
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine().foregroundStyle(Color.black.opacity(0.045))
                            AxisValueLabel().font(.system(size: 8))
                        }
                    }
                    .chartXAxis {
                        AxisMarks {
                            AxisValueLabel().font(.system(size: 8))
                        }
                    }
                    .frame(height: 120)
                } else {
                    chartPlaceholder(icon: "shoeprints.fill")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedSteps(progressSnapshot?.averageDailySteps))
                        .font(.title2.weight(.bold))
                        .minimumScaleFactor(0.70)
                        .lineLimit(1)
                    Text("avg. steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    changeIndicator(progressSnapshot?.stepsChangePercent)
                        .padding(.top, 7)

                    Text(comparisonLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 70, alignment: .leading)
            }
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            compactHeader("Consistency")

            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(green.opacity(0.08))
                        .frame(width: 78, height: 78)

                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 32))
                        .foregroundStyle(green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(activeDaysLast30) active days")
                        .font(.title2.weight(.bold))

                    Text("Last 30 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: Double(activeDaysLast30), total: 30)
                .tint(green)

            Text("\(consistencyPercentLast30)% of the last 30 days included training.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var personalRecordsCard: some View {
        let healthRecords = Array(personalRecords.prefix(2))
        let strengthRecords = Array(
            strengthWorkout.personalRecords
                .filter { $0.kind == .heaviestSet }
                .prefix(2)
        )
        let totalRecordCount = personalRecords.count + strengthWorkout.personalRecords.count

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Personal Records")
                    .font(.headline)
                Spacer()

                if totalRecordCount > healthRecords.count + strengthRecords.count {
                    Text("+\(totalRecordCount - healthRecords.count - strengthRecords.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(green)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if healthRecords.isEmpty && strengthRecords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "trophy")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text("No records yet")
                        .font(.caption.weight(.semibold))

                    Text("ATHLTH will surface verified records from Apple Health and strength workouts you log in ATHLTH.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(healthRecords) { record in
                    recordRow(
                        record.kind.title,
                        value: record.formattedValue,
                        date: record.date.formatted(.dateTime.month(.abbreviated).day().year()),
                        icon: record.kind.systemImage
                    )
                }

                if !healthRecords.isEmpty && !strengthRecords.isEmpty {
                    Divider()
                        .overlay(Color.black.opacity(0.05))
                }

                ForEach(strengthRecords) { record in
                    recordRow(
                        record.title,
                        value: record.value,
                        date: record.date.formatted(.dateTime.month(.abbreviated).day().year()),
                        icon: record.kind.systemImage
                    )
                }
            }
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var monthlyStatsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Monthly Stats")
                    .font(.headline)
                Spacer()
                Text(Date().formatted(.dateTime.month(.wide).year()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 14
            ) {
                statTile(
                    icon: "dumbbell.fill",
                    tint: green,
                    value: monthlySnapshot.map { String($0.workoutCount) } ?? "—",
                    label: "Workouts",
                    change: monthlySnapshot?.workoutChangePercent
                )

                statTile(
                    icon: "shoeprints.fill",
                    tint: blue,
                    value: formattedSteps(monthlySnapshot?.totalSteps),
                    label: "Steps",
                    change: monthlySnapshot?.totalStepsChangePercent
                )

                statTile(
                    icon: "moon.fill",
                    tint: purple,
                    value: monthlySnapshot?.averageSleepDuration.map { $0.shortDuration } ?? "—",
                    label: "Avg. Sleep",
                    change: monthlySnapshot?.sleepChangePercent
                )

                statTile(
                    icon: "clock.fill",
                    tint: green,
                    value: monthlySnapshot.map { $0.trainingDuration.shortDuration } ?? "—",
                    label: "Training",
                    change: monthlySnapshot?.trainingDurationChangePercent
                )
            }
        }
        .padding(16)
        .progressReferenceCard()
    }

    private var achievementsCard: some View {
        TrophyProgressCard()
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(width: 1, height: 100)
    }

    private func compactHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func overviewMetric(
        icon: String,
        tint: Color,
        value: String,
        title: String,
        change: Double?,
        footer: String
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.title3.weight(.bold))
                .minimumScaleFactor(0.68)
                .lineLimit(1)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let change {
                changeIndicator(change)
            } else {
                Text("—")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(footer)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func changeIndicator(_ change: Double?) -> some View {
        if let change {
            HStack(spacing: 2) {
                Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                Text("\(abs(change), specifier: "%.0f")%")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(change >= 0 ? green : Color.orange)
        } else {
            Text("—")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func formattedSteps(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Int(value.rounded()).formatted()
    }

    private var overviewTitle: String {
        switch period {
        case .week: return "Weekly Overview"
        case .month: return "Monthly Overview"
        case .threeMonths: return "3 Month Overview"
        case .year: return "Year Overview"
        }
    }

    private var comparisonLabel: String {
        switch period {
        case .week: return "vs. last week"
        case .month: return "vs. last month"
        case .threeMonths: return "vs. prior 3 mo."
        case .year: return "vs. last year"
        }
    }

    private var periodSummaryLabel: String {
        switch period {
        case .week: return "this week"
        case .month: return "this month"
        case .threeMonths: return "3 months"
        case .year: return "this year"
        }
    }

    private var periodDateLabel: String {
        let range = progressRange
        let start = range.start.formatted(.dateTime.month(.abbreviated).day())
        let end = range.end.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    private var stepsChartUpperBound: Double {
        let maximum = progressSnapshot?.buckets
            .compactMap(\.averageDailySteps)
            .max() ?? 0
        let rounded = ceil(maximum / 5_000) * 5_000
        return max(10_000, rounded)
    }

    private func bucketAxisLabel(_ date: Date) -> String {
        switch period {
        case .week:
            return date.formatted(.dateTime.weekday(.narrow))
        case .month, .threeMonths:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .year:
            return date.formatted(.dateTime.month(.abbreviated))
        }
    }

    @ViewBuilder
    private func chartPlaceholder(icon: String) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.025))
            .frame(height: 120)
            .overlay {
                Image(systemName: icon)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
    }

    private var progressGrouping: HealthProgressGrouping {
        switch period {
        case .week:
            return .day
        case .month, .threeMonths:
            return .week
        case .year:
            return .month
        }
    }

    private var progressRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()

        let start: Date
        let previousStart: Date

        switch period {
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
            previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: start)
                ?? start.addingTimeInterval(-604_800)

        case .month:
            start = calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
            previousStart = calendar.date(byAdding: .month, value: -1, to: start)
                ?? start.addingTimeInterval(-2_592_000)

        case .threeMonths:
            let currentMonth = calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
            start = calendar.date(byAdding: .month, value: -2, to: currentMonth)
                ?? currentMonth
            previousStart = calendar.date(byAdding: .month, value: -3, to: start)
                ?? start.addingTimeInterval(-7_776_000)

        case .year:
            start = calendar.dateInterval(of: .year, for: now)?.start
                ?? calendar.startOfDay(for: now)
            previousStart = calendar.date(byAdding: .year, value: -1, to: start)
                ?? start.addingTimeInterval(-31_536_000)
        }

        let elapsed = now.timeIntervalSince(start)
        let previousBoundary: Date

        switch period {
        case .week:
            previousBoundary = calendar.date(byAdding: .weekOfYear, value: 1, to: previousStart) ?? start
        case .month:
            previousBoundary = calendar.date(byAdding: .month, value: 1, to: previousStart) ?? start
        case .threeMonths:
            previousBoundary = calendar.date(byAdding: .month, value: 3, to: previousStart) ?? start
        case .year:
            previousBoundary = calendar.date(byAdding: .year, value: 1, to: previousStart) ?? start
        }

        let previousEnd = min(
            previousStart.addingTimeInterval(elapsed),
            previousBoundary
        )

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: previousEnd
        )
    }

    private var activeDaysLast30: Int {
        guard let days = consistencySnapshot?.activeWorkoutDays else {
            return 0
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today

        return Set(days.map { calendar.startOfDay(for: $0) })
            .filter { $0 >= start && $0 <= today }
            .count
    }

    private var consistencyPercentLast30: Int {
        Int(((Double(activeDaysLast30) / 30) * 100).rounded())
    }

    private var monthlyRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.dateInterval(of: .month, for: now)?.start
            ?? calendar.startOfDay(for: now)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: start)
            ?? start.addingTimeInterval(-2_592_000)
        let elapsed = now.timeIntervalSince(start)
        let previousBoundary = calendar.date(byAdding: .month, value: 1, to: previousStart)
            ?? start
        let previousEnd = min(
            previousStart.addingTimeInterval(elapsed),
            previousBoundary
        )

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: previousEnd
        )
    }

    private var consistencyRange: (
        start: Date,
        end: Date,
        previousStart: Date,
        previousEnd: Date
    ) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-7_776_000)
        let previousStart = calendar.date(byAdding: .day, value: -90, to: start)
            ?? start.addingTimeInterval(-7_776_000)

        return (
            start: start,
            end: now,
            previousStart: previousStart,
            previousEnd: start
        )
    }

    private func loadSupportingProgressData() async {
        guard health.healthDataAvailable, health.hasRequestedAuthorization else {
            monthlySnapshot = nil
            consistencySnapshot = nil
            personalRecords = []
            return
        }

        let month = monthlyRange
        let consistency = consistencyRange

        async let monthly = health.progressSnapshot(
            startDate: month.start,
            endDate: month.end,
            previousStartDate: month.previousStart,
            previousEndDate: month.previousEnd,
            grouping: .week
        )

        async let consistencyData = health.progressSnapshot(
            startDate: consistency.start,
            endDate: consistency.end,
            previousStartDate: consistency.previousStart,
            previousEndDate: consistency.previousEnd,
            grouping: .day
        )

        async let records = health.personalRecords()

        monthlySnapshot = try? await monthly
        consistencySnapshot = try? await consistencyData
        personalRecords = (try? await records) ?? []
    }

    private func loadProgressData() async {
        guard health.healthDataAvailable else {
            progressSnapshot = nil
            progressError = "Apple Health is unavailable on this device."
            return
        }

        guard health.hasRequestedAuthorization else {
            progressSnapshot = nil
            progressError = "Connect Apple Health to show your progress."
            return
        }

        progressLoading = true
        progressError = nil
        defer { progressLoading = false }

        let range = progressRange

        do {
            progressSnapshot = try await health.progressSnapshot(
                startDate: range.start,
                endDate: range.end,
                previousStartDate: range.previousStart,
                previousEndDate: range.previousEnd,
                grouping: progressGrouping
            )
        } catch {
            progressSnapshot = nil
            progressError = error.localizedDescription
        }
    }

    private func recordRow(
        _ title: String,
        value: String,
        date: String,
        icon: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(date)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.caption.weight(.bold))
        }
    }

    private func statTile(
        icon: String,
        tint: Color,
        value: String,
        label: String,
        change: Double?
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                if let change {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                        Text("\(abs(change), specifier: "%.0f")%")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(change >= 0 ? green : Color.orange)
                } else {
                    Text("—")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func achievementBadge(
        icon: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(45))

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 58)

            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func goalRow(
        icon: String,
        title: String,
        detail: String,
        progress: Double,
        progressText: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(green)
                .frame(width: 34, height: 34)
                .background(green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(progressText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(green)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.055))
                        Capsule()
                            .fill(green)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

extension View {
    func progressReferenceCard() -> some View {
        self
            .background(
                Color.white.opacity(0.97),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 14, x: 0, y: 7)
    }
}

struct ATHLTHProfileView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var trophyStore: TrophyStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var goalStore: GoalStore

    @State private var performanceStats: ProfilePerformanceStats?
    @State private var performanceStatsLoading = false

    var body: some View {
        ScrollView {
                VStack(spacing: 18) {
                    ATHLTHCard {
                        HStack(spacing: 18) {
                            profileAvatar

                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.profile.displayName)
                                    .font(.title2.weight(.bold))

                                Text("@\(session.profile.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if !session.profile.bio.isEmpty {
                                    Text(session.profile.bio)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .padding(.top, 2)
                                }

                                if settings.showTrainingStatusOnProfile {
                                    Label(
                                        session.profile.presence.state == .training
                                            ? "Training now"
                                            : "Ready to train",
                                        systemImage: session.profile.presence.state == .training
                                            ? "figure.run"
                                            : "circle.fill"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.accent)
                                    .padding(.top, 3)
                                }

                                if settings.showTrainingFocusOnProfile,
                                   let focus = session.onboardingProfile?.trainingFocus {
                                    HStack(spacing: 6) {
                                        Label(
                                            focus.title,
                                            systemImage: focus.systemImage
                                        )
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(
                                            ATHLTHTheme.accentSoft,
                                            in: Capsule()
                                        )

                                        if let currentGoal = session.onboardingProfile?.currentGoal {
                                            Text(currentGoal.type.title)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 5)
                                                .background(
                                                    Color.primary.opacity(0.055),
                                                    in: Capsule()
                                                )
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }

                            Spacer()

                            NavigationLink {
                                ATHLTHEditProfileView()
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(ATHLTHTheme.accentDeep)
                                    .frame(width: 42, height: 42)
                                    .background(
                                        ATHLTHTheme.accentSoft,
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit Profile")
                        }
                    }

                    if settings.shouldShowProfileSetupPrompt {
                        profileSetupPrompt
                    }

                    if settings.showCurrentGoalOnProfile,
                       let primaryGoal = goalStore.primaryGoal {
                        NavigationLink {
                            GoalDetailView(goalID: primaryGoal.id)
                        } label: {
                            currentFocusCard(primaryGoal)
                        }
                        .buttonStyle(.plain)
                    }

                    if settings.showProfileStatsOnProfile {
                        profileStatsRow
                    }

                    if settings.showPerformanceStatsOnProfile {
                        ProfilePerformanceSection(
                            stats: performanceStats,
                            isLoading: performanceStatsLoading
                        )
                    }

                    if settings.showWorkoutHistoryOnProfile {
                        WorkoutHistoryPreviewSection()
                    }

                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("ATHLTH")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await loadPerformanceStats(forceRefresh: true)
                await social.refresh()

                if social.privacy?.sharePerformanceStats == true {
                    await social.syncOwnPerformance(performanceStats)
                }
                if social.privacy?.shareTrophyCabinet == true {
                    await social.syncOwnTrophies(trophyStore.showcaseTrophies)
                }
            }
            .task {
                await loadPerformanceStats()
                await social.refresh()

                if social.privacy?.sharePerformanceStats == true {
                    await social.syncOwnPerformance(performanceStats)
                }
                if social.privacy?.shareTrophyCabinet == true {
                    await social.syncOwnTrophies(trophyStore.showcaseTrophies)
                }
            }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ATHLTHSettingsView()
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private var profileSetupPrompt: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Complete your profile")
                        .font(.headline)

                    Text("Choose your training focus, what you want on your profile, and what other people are allowed to see.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    NavigationLink {
                        ATHLTHProfileSetupView()
                    } label: {
                        Text("Set up profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accent)
                            .padding(.top, 3)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    settings.dismissProfileSetupPrompt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Color.primary.opacity(0.045),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss profile setup")
            }
        }
    }

    private var completedGoalCount: Int {
        goalStore.goals.filter { $0.status == .completed }.count
    }

    private var profileStatsRow: some View {
        HStack(spacing: 8) {
            compactProfileStat(
                value: performanceStats?.totalWorkoutCount.formatted() ?? "—",
                title: "Workouts"
            )

            compactProfileStat(
                value: completedGoalCount.formatted(),
                title: "Goals"
            )

            NavigationLink {
                TrophyCollectionView()
            } label: {
                compactProfileStat(
                    value: trophyStore.unlockedCount.formatted(),
                    title: "Trophies"
                )
            }
            .buttonStyle(.plain)

            compactProfileStat(
                value: session.savedRoutes.count.formatted(),
                title: "Routes"
            )
        }
    }

    private func compactProfileStat(
        value: String,
        title: String
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        }
    }

    private func currentFocusCard(_ goal: ATHLTHGoal) -> some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: goal.category.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("CURRENT FOCUS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)

                    Text(goal.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("\(Int((goal.progress * 100).rounded()))% complete")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.accent)

                        if let deadline = goal.deadline {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(deadline.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(value: goal.progress)
                        .tint(ATHLTHTheme.accent)
                        .padding(.top, 2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let avatarURL = session.profile.avatarURL {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Circle()
                        .fill(ATHLTHTheme.accentSoft)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(ATHLTHTheme.accent)
                        }
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(ATHLTHTheme.border, lineWidth: 1)
            }
        } else {
            Circle()
                .fill(ATHLTHTheme.accentSoft)
                .frame(width: 96, height: 96)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(ATHLTHTheme.accent)
                }
        }
    }

    @MainActor
    private func loadPerformanceStats(forceRefresh: Bool = false) async {
        guard health.hasRequestedAuthorization else {
            performanceStats = nil
            return
        }

        performanceStatsLoading = true
        defer { performanceStatsLoading = false }

        performanceStats = try? await health.profilePerformanceStats(
            forceRefresh: forceRefresh
        )
    }

    @ViewBuilder
    private func recentActivity(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(ATHLTHTheme.accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
