import Charts
import Combine
import MapKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ProductRootTabView: View {
    @EnvironmentObject private var workoutMirroring: WorkoutMirroringStore
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ATHLTHHomeView { tab in
                selectedTab = tab
            }
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
        .tint(ATHLTHTheme.accentDeep)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
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
    var onSelectTab: (Int) -> Void = { _ in }

    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var notifications: ATHLTHNotificationStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var community: CommunityEventStore
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var challenges: ChallengeStore

    @State private var homeStreakDays: [Date]?
    @State private var selectedHomeStrengthSession: PlannedSession?
    @State private var pendingHomeQuickStartKind: WorkoutKind?
    @State private var pendingHomePlanSession: PlannedSession?
    @State private var showingHomeStrengthWorkout = false
    @State private var homeWatchTransferMessage: String?
    @State private var homeWatchTransferError: String?

    var body: some View {
        NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: ATHLTHTheme.premiumGold.opacity(0.70)
            ) {
                ZStack(alignment: .topTrailing) {
                    ATHLTHTabHero(
                        imageName: "HomeHero",
                        title: greetingTitle,
                        subtitle:
                            session.profile.presence.state == .training
                                ? "Training now · \(session.profile.presence.workoutTitle ?? "Workout")"
                                : "Today, training and recovery at a glance.",
                        height: 190,
                        alignment: .leading,
                        focalOffsetX: 18,
                        focalOffsetY: 14
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
                                        .padding(
                                            .horizontal,
                                            homeInboxUnreadCount > 9 ? 2 : 0
                                        )
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
                                            Circle()
                                                .stroke(.white, lineWidth: 1.5)
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
                    .padding(.top, 52)
                    .padding(.trailing, 12)
                }
            } content: {
                LazyVStack(spacing: 18) {
                    homeTodayCard

                    if shouldShowGettingStarted {
                        HomeGettingStartedCard(
                            healthConnected: health.hasRequestedAuthorization,
                            hasPlan: session.activePlan != nil,
                            hasGoal: !goalStore.activeGoals.isEmpty
                        )
                    }

                    if health.hasRequestedAuthorization {
                        ATHLTHCard {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Daily Readiness")
                                        .font(.title3.weight(.bold))
                                    Text(homeHealthSourceText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if let score = health.recovery.score {
                                    Text("\(score)")
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(
                                            readinessTint
                                        )
                                }
                            }

                            HStack(alignment: .top, spacing: 9) {
                                HomeDayStatus(
                                    title: "Move",
                                    value: moveValue,
                                    subtitle: moveSubtitle,
                                    icon: "flame.fill",
                                    progress: moveProgress,
                                    tint: .orange
                                )

                                HomeDayStatus(
                                    title: "Recovery",
                                    value: recoveryValue,
                                    subtitle: health.recovery.state.title,
                                    icon: health.recovery.state.systemImage,
                                    progress: health.recovery.score.map {
                                        Double($0) / 100
                                    },
                                    tint: ATHLTHTheme.recoveryBlue
                                )

                                HomeDayStatus(
                                    title: "Sleep",
                                    value: sleepValue,
                                    subtitle: sleepSubtitle,
                                    icon: "moon.fill",
                                    progress:
                                        health.sleep.totalAsleep > 0
                                            ? min(
                                                health.sleep.totalAsleep /
                                                    (8 * 3_600),
                                                1
                                            )
                                            : nil,
                                    tint: .purple
                                )
                            }
                            .padding(.top, 14)

                            if let insight = homeInsight {
                                Divider()
                                    .padding(.vertical, 12)

                                Button {
                                    onSelectTab(2)
                                } label: {
                                    HStack(alignment: .top, spacing: 11) {
                                        Image(systemName: insight.icon)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(readinessTint)
                                            .frame(width: 34, height: 34)
                                            .background(
                                                readinessTint.opacity(0.10),
                                                in: RoundedRectangle(
                                                    cornerRadius: 11,
                                                    style: .continuous
                                                )
                                            )

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(insight.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(ATHLTHTheme.primaryText)

                                            Text(insight.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HomeThisWeekCard(
                        plan: session.activePlan,
                        workouts: health.workouts,
                        streakCount: homeStreakCount
                    ) {
                        onSelectTab(3)
                    }

                    HomeActivitySection()

                    HomeHappeningCard(
                        challenges: challenges.visibleChallenges,
                        events: community.upcomingEvents
                    ) {
                        onSelectTab(4)
                    }

                    HomeAroundYouSection()
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .sheet(item: $selectedHomeStrengthSession) { workout in
                WorkoutStartOptionsView(
                    session: workout,
                    trainingDeviceProvider: settings.trainingDeviceProvider,
                    watchConnected:
                        settings.trainingDeviceProvider == .appleWatch &&
                        watchConnection.isReady,
                    defaultCapture: settings.preferredWorkoutCapture,
                    defaultTracking: settings.defaultStrengthTracking
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
                                session.beginTrainingStatus(for: workout)
                                strengthWorkout.start(
                                    session: workout,
                                    watchSessionID: UUID(),
                                    trackingMode: trackingMode,
                                    captureDevice: .appleWatch
                                )
                                showingHomeStrengthWorkout = true
                            } catch {
                                homeWatchTransferError =
                                    error.localizedDescription
                            }
                        } else {
                            session.beginTrainingStatus(for: workout)
                            strengthWorkout.start(
                                session: workout,
                                watchSessionID: nil,
                                trackingMode: trackingMode,
                                captureDevice: .iPhone
                            )
                            showingHomeStrengthWorkout = true
                        }
                    }
                }
            }
            .sheet(item: $pendingHomeQuickStartKind) { kind in
                QuickWorkoutStartSheet(
                    kind: kind,
                    trainingDeviceProvider: settings.trainingDeviceProvider,
                    watchConnected:
                        settings.trainingDeviceProvider == .appleWatch &&
                        watchConnection.isReady
                ) { selectedFriends in
                    let planned = pendingHomePlanSession

                    Task { @MainActor in
                        await social.beginWorkoutWithFriends(
                            title: planned?.title ?? kind.title,
                            kind: kind,
                            friends: selectedFriends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username
                        )

                        if let planned {
                            startHomePlannedWorkoutOnWatch(planned)
                        } else {
                            startHomeQuickWorkoutOnWatch(kind)
                        }

                        pendingHomePlanSession = nil
                    }
                }
            }
            .fullScreenCover(isPresented: $showingHomeStrengthWorkout) {
                ActiveStrengthWorkoutView()
                    .environmentObject(strengthWorkout)
                    .environmentObject(session)
            }
            .alert(
                "ATHLTH",
                isPresented: Binding(
                    get: {
                        homeWatchTransferMessage != nil ||
                        homeWatchTransferError != nil
                    },
                    set: { visible in
                        if !visible {
                            homeWatchTransferMessage = nil
                            homeWatchTransferError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    homeWatchTransferMessage = nil
                    homeWatchTransferError = nil
                }
            } message: {
                Text(
                    homeWatchTransferError ??
                    homeWatchTransferMessage ??
                    ""
                )
            }
            .refreshable {
                async let communityRefresh: Void = community.refresh()
                async let activityRefresh: Void =
                    social.refreshHomeFeed(force: true)

                if !health.shouldDeferAutomaticHealthWork {
                    await health.refreshAll()

                    async let streakRefresh: Void = loadHomeStreak()
                    async let goalsRefresh: Void =
                        goalStore.refreshAutomaticMilestones(
                            health: health,
                            strength: strengthWorkout
                        )

                    _ = await (
                        streakRefresh,
                        goalsRefresh
                    )
                } else {
                    await loadHomeStreak()
                }

                _ = await (communityRefresh, activityRefresh)
            }
            .task {
                async let communityRefresh: Void = community.refresh()
                async let activityRefresh: Void = social.refreshHomeFeed()

                guard !health.shouldDeferAutomaticHealthWork else {
                    await loadHomeStreak()
                    _ = await (communityRefresh, activityRefresh)
                    return
                }

                if health.lastSuccessfulRefreshAt == nil {
                    await health.refreshAll()
                }

                async let streakRefresh: Void = loadHomeStreak()
                async let goalsRefresh: Void =
                    goalStore.refreshAutomaticMilestones(
                        health: health,
                        strength: strengthWorkout
                    )

                _ = await (
                    streakRefresh,
                    goalsRefresh,
                    communityRefresh,
                    activityRefresh
                )
            }
            .onChange(of: strengthWorkout.workoutHistory.count) {
                Task {
                    await loadHomeStreak()
                }
            }
            .onChange(of: health.workouts.count) {
                Task {
                    await loadHomeStreak()
                }
            }
        }
    }

    @MainActor
    private func loadHomeStreak() async {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(
            byAdding: .day,
            value: -90,
            to: today
        ) ?? now.addingTimeInterval(-7_776_000)

        // Native ATHLTH sessions count even when the user has chosen not to
        // grant Health write/read access. This keeps streak an ATHLTH training
        // concept rather than making it dependent on a wearable.
        var activeDays = Set(
            strengthWorkout.workoutHistory
                .filter {
                    $0.isFinished &&
                    $0.startedAt >= start &&
                    $0.startedAt <= now
                }
                .map {
                    calendar.startOfDay(for: $0.startedAt)
                }
        )

        if health.healthDataAvailable,
           health.hasRequestedAuthorization {
            do {
                let healthDays = try await health.activeWorkoutDays(
                    startDate: start,
                    endDate: now
                )

                activeDays.formUnion(
                    healthDays.map {
                        calendar.startOfDay(for: $0)
                    }
                )
            } catch {
                // Keep the ATHLTH-native days instead of turning a temporary
                // Health query failure into a lost streak.
            }
        }

        homeStreakDays = Array(activeDays).sorted()
    }

    @MainActor
    private func loadHomeWeek() async {
        guard health.hasRequestedAuthorization,
              !health.shouldDeferAutomaticHealthWork
        else {
            homeWeekSnapshot = nil
            return
        }

        homeWeekLoading = true
        defer { homeWeekLoading = false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDate =
            calendar.date(byAdding: .day, value: 1, to: today) ??
            Date()
        let startDate =
            calendar.date(byAdding: .day, value: -6, to: today) ??
            today.addingTimeInterval(-6 * 86_400)
        let previousEndDate = startDate
        let previousStartDate =
            calendar.date(
                byAdding: .day,
                value: -7,
                to: previousEndDate
            ) ??
            previousEndDate.addingTimeInterval(-7 * 86_400)

        do {
            homeWeekSnapshot = try await health.progressSnapshot(
                startDate: startDate,
                endDate: endDate,
                previousStartDate: previousStartDate,
                previousEndDate: previousEndDate,
                grouping: .day
            )
        } catch {
            homeWeekSnapshot = nil
        }
    }

    private var homeInboxUnreadCount: Int {
        messaging.unreadCount + messaging.messageRequestCount
    }

    private var homeInboxBadgeText: String {
        homeInboxUnreadCount > 99 ? "99+" : "\(homeInboxUnreadCount)"
    }

    private var homeStreakCount: Int {
        guard let homeStreakDays,
              !homeStreakDays.isEmpty
        else {
            return 0
        }

        let calendar = Calendar.current
        let active = Set(
            homeStreakDays.map {
                calendar.startOfDay(for: $0)
            }
        )
        let today = calendar.startOfDay(for: Date())

        let startDay: Date
        if active.contains(today) {
            startDay = today
        } else if let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: today
        ),
        active.contains(yesterday) {
            startDay = yesterday
        } else {
            return 0
        }

        var streak = 0
        var cursor = startDay

        while active.contains(cursor) {
            streak += 1

            guard let previous = calendar.date(
                byAdding: .day,
                value: -1,
                to: cursor
            ) else {
                break
            }

            cursor = previous
        }

        return streak
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
                return "Garmin sync pending · Apple Health not connected"
            case .appleWatch:
                return watchConnection.isReady
                    ? "Apple Watch connected · Apple Health not connected"
                    : "Apple Watch setup incomplete"
            case .none:
                return "No health source connected"
            }
        }

        if !health.hasTrainingHealthData {
            switch settings.trainingDeviceProvider {
            case .appleWatch:
                return watchConnection.isReady
                    ? "Apple Health configured · no training data yet"
                    : "Apple Health configured · Watch setup incomplete"
            case .garmin:
                return "Apple Health configured · Garmin sync pending"
            case .none:
                return "Apple Health configured · no training data yet"
            }
        }

        switch settings.trainingDeviceProvider {
        case .appleWatch:
            return watchConnection.isReady
                ? "Apple Health + Apple Watch"
                : "Apple Health · Apple Watch setup incomplete"
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

    private var shouldShowMoveSummary: Bool {
        health.training.activeEnergyKilocaloriesToday != nil ||
            health.training.exerciseMinutesToday != nil ||
            health.training.moveGoalKilocaloriesToday != nil
    }

    private var shouldShowSleepSummary: Bool {
        health.sleep.totalAsleep > 0
    }

    private var shouldShowRecoverySummary: Bool {
        health.recovery.score != nil ||
            health.heart.hrvMilliseconds != nil ||
            health.heart.restingHeartRate != nil ||
            health.recovery.baselineDays > 0
    }

    private var shouldShowAnyDaySummary: Bool {
        shouldShowMoveSummary ||
            shouldShowRecoverySummary ||
            shouldShowSleepSummary
    }

    private var homeNoHealthDetail: String {
        if !health.hasRequestedAuthorization {
            switch settings.trainingDeviceProvider {
            case .appleWatch:
                if watchConnection.isReady {
                    return "Your Apple Watch is connected, but ATHLTH still needs Apple Health access before health metrics appear. Training plans, strength logging and social features remain available."
                }
                return "Apple Watch setup is incomplete and Apple Health is not connected. ATHLTH hides unavailable health cards while training plans, strength logging and social features remain available."
            case .garmin:
                return "Garmin sync is not active yet and Apple Health is not connected. ATHLTH keeps unavailable health cards out of the way."
            case .none:
                return "No watch or Apple Health is connected. ATHLTH stays focused on training plans, strength logging, routes, challenges and social features you can use without wearable data."
            }
        }

        return "Apple Health is configured. Health cards appear automatically when compatible readable data becomes available, so ATHLTH does not fill your dashboard with empty metrics."
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

    private var homeNextUp: HomeNextUpItem? {
        let now = Date()
        let horizon = now.addingTimeInterval(24 * 60 * 60)

        var candidates: [HomeNextUpItem] = []

        if let plan = session.activePlan {
            for week in plan.weeks {
                for day in week.days {
                    for workout in day.sessions {
                        guard let start = workout.scheduledStart,
                              start >= now,
                              start <= horizon
                        else {
                            continue
                        }

                        candidates.append(
                            .workout(
                                planID: plan.id,
                                workout: workout
                            )
                        )
                    }
                }
            }
        }

        for event in community.upcomingEvents {
            guard event.event.startsAt <= horizon,
                  event.event.creatorID == session.profile.userID ||
                    community.isJoined(event)
            else {
                continue
            }

            candidates.append(.event(event))
        }

        return candidates.min {
            $0.date < $1.date
        }
    }

    @ViewBuilder
    private func homeNextUpCard(
        _ item: HomeNextUpItem
    ) -> some View {
        switch item {
        case .workout(let planID, let workout):
            NavigationLink {
                PlannedWorkoutDetailView(
                    planID: planID,
                    workout: workout,
                    isHealthCompleted: false
                )
            } label: {
                homeNextUpContent(item)
            }
            .buttonStyle(.plain)

        case .event(let event):
            NavigationLink {
                CommunityEventDetailView(eventID: event.id)
            } label: {
                homeNextUpContent(item)
            }
            .buttonStyle(.plain)
        }
    }

    private func homeNextUpContent(
        _ item: HomeNextUpItem
    ) -> some View {
        ATHLTHCard {
            HStack(spacing: 13) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.tint)
                    .frame(width: 44, height: 44)
                    .background(
                        item.tint.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT UP")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep.opacity(0.72)
                        )

                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(1)

                    Text(
                        item.date.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
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

private enum HomeNextUpItem {
    case workout(planID: UUID, workout: PlannedSession)
    case event(CommunityEventItem)

    var date: Date {
        switch self {
        case .workout(_, let workout):
            return workout.scheduledStart ?? .distantFuture
        case .event(let event):
            return event.event.startsAt
        }
    }

    var title: String {
        switch self {
        case .workout(_, let workout):
            return workout.title
        case .event(let event):
            return event.event.title
        }
    }

    var icon: String {
        switch self {
        case .workout(_, let workout):
            return workout.kind.systemImage
        case .event(let event):
            return event.event.activityType.systemImage
        }
    }

    var tint: Color {
        switch self {
        case .workout(_, let workout):
            switch workout.kind {
            case .running: return .green
            case .walking: return .blue
            case .strength: return .purple
            case .mobility: return .teal
            case .recovery: return .indigo
            case .custom: return ATHLTHTheme.accent
            }
        case .event:
            return .purple
        }
    }
}

private struct HomeDayStatus: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let progress: Double?
    var tint: Color = ATHLTHTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    tint.opacity(0.10),
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
                    .tint(tint)
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
            LinearGradient(
                colors: [
                    tint.opacity(0.055),
                    ATHLTHTheme.cardWarm.opacity(0.62)
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
            .stroke(ATHLTHTheme.border, lineWidth: 1)
        }
    }
}

private struct HomeCurrentStreakCard: View {
    let activeWorkoutDays: [Date]?

    private var currentWeekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(
            of: .weekOfYear,
            for: Date()
        )?.start ?? calendar.startOfDay(for: Date())

        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private func isWorkoutDay(_ date: Date) -> Bool {
        guard let activeWorkoutDays else { return false }

        let calendar = Calendar.current
        return activeWorkoutDays.contains {
            calendar.isDate($0, inSameDayAs: date)
        }
    }

    private var workoutStreak: Int {
        guard let activeWorkoutDays,
              !activeWorkoutDays.isEmpty
        else {
            return 0
        }

        let calendar = Calendar.current
        let active = Set(
            activeWorkoutDays.map {
                calendar.startOfDay(for: $0)
            }
        )
        let today = calendar.startOfDay(for: Date())

        let startDay: Date
        if active.contains(today) {
            startDay = today
        } else if let yesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: today
        ),
        active.contains(yesterday) {
            startDay = yesterday
        } else {
            return 0
        }

        var streak = 0
        var cursor = startDay

        while active.contains(cursor) {
            streak += 1

            guard let previous = calendar.date(
                byAdding: .day,
                value: -1,
                to: cursor
            ) else {
                break
            }

            cursor = previous
        }

        return streak
    }

    private var title: String {
        guard activeWorkoutDays != nil else {
            return "Streak"
        }

        if workoutStreak == 0 {
            return "Start today"
        }

        return "\(workoutStreak) day\(workoutStreak == 1 ? "" : "s")"
    }

    private var subtitle: String {
        guard activeWorkoutDays != nil else {
            return "Syncing workout days…"
        }

        switch workoutStreak {
        case 0:
            return "One workout starts your streak."
        case 1:
            return "First day — keep it going."
        default:
            return "Keep the momentum going."
        }
    }

    private var streakIsActive: Bool {
        workoutStreak > 0
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        streakIsActive
                            ? Color.orange.opacity(0.13)
                            : ATHLTHTheme.accentSoft.opacity(0.70)
                    )

                if activeWorkoutDays == nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            streakIsActive
                                ? Color.orange
                                : ATHLTHTheme.mutedText.opacity(0.72)
                        )
                }
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    if streakIsActive {
                        Text("STREAK")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Color.orange.opacity(0.10),
                                in: Capsule()
                            )
                    }
                }

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(currentWeekDays, id: \.self) { day in
                    streakDay(day)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: streakIsActive
                    ? [
                        Color.orange.opacity(0.075),
                        Color.white.opacity(0.90)
                    ]
                    : [
                        Color.white.opacity(0.84),
                        ATHLTHTheme.accentSoft.opacity(0.24)
                    ],
                startPoint: .leading,
                endPoint: .trailing
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
                streakIsActive
                    ? Color.orange.opacity(0.14)
                    : ATHLTHTheme.border.opacity(0.72),
                lineWidth: 1
            )
        }
        .shadow(
            color: streakIsActive
                ? Color.orange.opacity(0.055)
                : Color.black.opacity(0.025),
            radius: 12,
            x: 0,
            y: 6
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            activeWorkoutDays == nil
                ? "Workout streak is syncing"
                : workoutStreak > 0
                    ? "Current workout streak, \(workoutStreak) days"
                    : "No current workout streak"
        )
    }

    @ViewBuilder
    private func streakDay(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let completed = isWorkoutDay(day)
        let isFuture = day > calendar.startOfDay(for: Date())

        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(
                        completed
                            ? Color.orange
                            : Color.black.opacity(isFuture ? 0.025 : 0.055)
                    )
                    .frame(width: 17, height: 17)

                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }

                if isToday && !completed {
                    Circle()
                        .stroke(Color.orange.opacity(0.72), lineWidth: 1.4)
                        .frame(width: 17, height: 17)
                }
            }

            Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 7, weight: isToday ? .bold : .semibold))
                .foregroundStyle(
                    isToday
                        ? ATHLTHTheme.primaryText
                        : ATHLTHTheme.mutedText
                )
        }
        .frame(width: 20)
    }
}

private struct PlannedWorkoutSelection: Identifiable {
    let planID: UUID
    let workout: PlannedSession
    let isHealthCompleted: Bool

    var id: UUID { workout.id }
}

struct ATHLTHTrainView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strengthWorkout: StrengthWorkoutStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var watchConnection: AppleWatchConnectionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningWorkoutLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var social: SocialStore

    @State private var selectedSection = 0
    @State private var watchTransferMessage: String?
    @State private var watchTransferError: String?
    @State private var selectedStrengthSession: PlannedSession?
    @State private var selectedPlanWorkout: PlannedWorkoutSelection?
    @State private var pendingQuickStartKind: WorkoutKind?
    @State private var pendingRunningTemplate: RunningWorkoutTemplate?
    @State private var showingCustomQuickStart = false
    @State private var showingStrengthWorkout = false

    var body: some View {
        NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: Color.green.opacity(0.55)
            ) {
                ATHLTHTabHero(
                    imageName: "TrainHero",
                        title: "Train",
                        subtitle: "Build a stronger, healthier you.",
                        height: 190,
                        alignment: .leading,
                        focalOffsetX: -18,
                    focalOffsetY: 18
                )
            } content: {
                VStack(spacing: 18) {
                    ATHLTHPremiumSegmentedControl(
                        titles: ["Today", "Plan", "Library"],
                        selection: $selectedSection
                    )

                    switch selectedSection {
                    case 1:
                        AdvancedPlannerView {
                            selectedSection = 2
                        }
                    case 2:
                        libraryContent
                    default:
                        todayContent
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .sheet(item: $selectedPlanWorkout) { selection in
                PlannedWorkoutDetailView(
                    planID: selection.planID,
                    workout: selection.workout,
                    isHealthCompleted: selection.isHealthCompleted
                )
                .environmentObject(session)
            }
            .sheet(item: $selectedStrengthSession) { workout in
                WorkoutStartOptionsView(
                    session: workout,
                    trainingDeviceProvider: settings.trainingDeviceProvider,
                    watchConnected:
                        settings.trainingDeviceProvider == .appleWatch &&
                        watchConnection.isReady,
                    defaultCapture: settings.preferredWorkoutCapture,
                    defaultTracking: settings.defaultStrengthTracking
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
            .sheet(item: $pendingRunningTemplate) { workout in
                QuickWorkoutStartSheet(
                    kind: .running,
                    trainingDeviceProvider: settings.trainingDeviceProvider,
                    watchConnected:
                        settings.trainingDeviceProvider == .appleWatch &&
                        watchConnection.isReady
                ) { selectedFriends in
                    Task { @MainActor in
                        await social.beginWorkoutWithFriends(
                            title: workout.title,
                            kind: .running,
                            friends: selectedFriends,
                            creatorName: session.profile.displayName,
                            creatorUsername: session.profile.username
                        )
                        startRunningTemplate(workout)
                    }
                }
            }
            .sheet(isPresented: $showingCustomQuickStart) {
                CustomQuickStartSheet(
                    trainingDeviceProvider: settings.trainingDeviceProvider,
                    watchConnected:
                        settings.trainingDeviceProvider == .appleWatch &&
                        watchConnection.isReady
                ) { configuration in
                    startCustomWorkoutOnWatch(configuration)
                }
            }
            .fullScreenCover(isPresented: $showingStrengthWorkout) {
                ActiveStrengthWorkoutView()
                    .environmentObject(strengthWorkout)
                    .environmentObject(session)
            }
            .task {
                await exerciseLibrary.refresh()
            }
            .alert("ATHLTH", isPresented: Binding(
                get: {
                    watchTransferMessage != nil ||
                    watchTransferError != nil
                },
                set: { newValue in
                    if !newValue {
                        watchTransferMessage = nil
                        watchTransferError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    watchTransferMessage = nil
                    watchTransferError = nil
                }
            } message: {
                Text(
                    watchTransferError ??
                    watchTransferMessage ??
                    ""
                )
            }
        }
    }

    @ViewBuilder
    private var todayContent: some View {
        if let plan = session.activePlan {
            todaysPlanCard(plan)
        } else {
            noActivePlanCard
        }

        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Quick Start",
                actionTitle: "Get moving now"
            )

            HStack(spacing: 8) {
                quickStartTile(
                    title: "Run",
                    subtitle: "Outdoor",
                    icon: "figure.run",
                    enabled: quickStartAvailable(.running)
                ) {
                    handleQuickStart(.running)
                }

                quickStartTile(
                    title: "Walk",
                    subtitle: "Outdoor",
                    icon: "figure.walk",
                    enabled: quickStartAvailable(.walking)
                ) {
                    handleQuickStart(.walking)
                }

                quickStartTile(
                    title: "Strength",
                    subtitle: "Gym / Home",
                    icon: "dumbbell.fill",
                    enabled: quickStartAvailable(.strength)
                ) {
                    handleQuickStart(.strength)
                }

                quickStartTile(
                    title: "Custom",
                    subtitle: "Build yours",
                    icon: "plus",
                    enabled: true
                ) {
                    showingCustomQuickStart = true
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


    }

    @ViewBuilder
    private var libraryContent: some View {
        TrainingPlanManagerView {
            selectedSection = 1
        }

        ATHLTHCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Routes")
                        .font(.title3.weight(.bold))
                    Text("Create and save routes inside ATHLTH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                .controlSize(.small)
                .tint(ATHLTHTheme.accent)
            }

            if let route = session.savedRoutes.first,
               let region = routeRegion(route) {
                NavigationLink {
                    SavedRoutesView()
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Map(initialPosition: .region(region)) {
                            MapPolyline(
                                coordinates: route.coordinates.map(\.coordinate)
                            )
                            .stroke(ATHLTHTheme.accent, lineWidth: 5)
                        }
                        .allowsHitTesting(false)
                        .frame(height: 130)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                Text(
                                    "\(route.distanceKilometers, specifier: "%.1f") km · \(Int(route.elevationGainMeters ?? 0)) m ascent"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 12)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(ATHLTHTheme.accent)
                    Text("No saved routes yet. Create your first route in ATHLTH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 12)
            }
        }

        ATHLTHCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workout Library")
                    .font(.title3.weight(.bold))
                Text("Choose a complete workout or use exercises to build your own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                NavigationLink {
                    RunningWorkoutLibraryView(
                        onStart: { workout in
                            pendingRunningTemplate = workout
                        }
                    )
                } label: {
                    libraryRow(
                        title: "Running Workouts",
                        subtitle: "\(runningWorkoutLibrary.allTemplates.count) structured workouts · start, schedule or customize",
                        icon: "figure.run",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    libraryRow(
                        title: "Exercise Library",
                        subtitle: exerciseLibrary.repDBExercises.isEmpty
                            ? "Strength exercises and your own custom movements"
                            : "\(exerciseLibrary.repDBExercises.count) exercises · use them to build strength workouts",
                        icon: "dumbbell.fill",
                        tint: .purple
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
    }

    private func libraryRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 13)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    @ViewBuilder
    private func quickStartTile(
        title: String,
        subtitle: String,
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(height: 26)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(.horizontal, 4)
            .background(
                ATHLTHTheme.accentSoft.opacity(enabled ? 0.72 : 0.34),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(
                        enabled
                            ? ATHLTHTheme.accent.opacity(0.10)
                            : ATHLTHTheme.border,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.48)
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

    private var quickStartKinds: [WorkoutKind] {
        switch settings.trainingDeviceProvider {
        case .appleWatch:
            return [.running, .walking, .strength]
        case .garmin:
            return [.strength]
        case .none:
            // Outdoor quick capture currently requires a supported wearable.
            // Keep the iPhone-native strength flow available and avoid
            // presenting dead or empty wearable-only choices.
            return [.strength]
        }
    }

    private func quickStartAvailable(_ kind: WorkoutKind) -> Bool {
        if kind == .strength {
            return strengthWorkout.activeWorkout == nil
        }

        guard watchWorkoutKind(for: kind) != nil else {
            return false
        }

        switch settings.trainingDeviceProvider {
        case .appleWatch:
            return !watchConnection.workoutLaunchInProgress
        case .garmin, .none:
            return false
        }
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
            return "iPhone"
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
            EmptyView()
        }
    }

    private func startCustomWorkoutOnWatch(
        _ configuration: CustomQuickWorkoutConfiguration
    ) {
        guard settings.trainingDeviceProvider == .appleWatch,
              watchConnection.isReady
        else {
            return
        }

        Task {
            do {
                try await watchConnection.startWorkoutOnWatch(
                    configuration.activity.watchKind
                )
                watchTransferMessage =
                    "\(configuration.title) started on Apple Watch · \(configuration.detail)."
            } catch {
                watchTransferError = error.localizedDescription
            }
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

    private func startRunningTemplate(
        _ workout: RunningWorkoutTemplate
    ) {
        guard settings.trainingDeviceProvider == .appleWatch,
              watchConnection.isReady
        else {
            watchTransferError =
                "Connect Apple Watch to start a live running workout from the library."
            return
        }

        if let routeID = workout.routeID,
           let route = session.savedRoutes.first(where: { $0.id == routeID }) {
            do {
                try watchConnection.sendRoute(route)
            } catch {
                watchTransferError = error.localizedDescription
                return
            }
        }

        Task {
            do {
                try await watchConnection.startWorkoutOnWatch(.running)
                watchTransferMessage =
                    "\(workout.title) started on Apple Watch."
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

    @ViewBuilder
    private func todaysPlanCard(_ plan: TrainingPlan) -> some View {
        let sessions = todaySessions(in: plan)
        let healthCompletedIDs = healthCompletedTodaySessionIDs(sessions)
        let manuallyCompletedIDs = manuallyCompletedTodaySessionIDs(
            planID: plan.id,
            sessions: sessions
        )

        ATHLTHCard {
            HStack(spacing: 10) {
                Text("Today's Plan")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    selectedSection = 1
                } label: {
                    HStack(spacing: 5) {
                        Text("View Plan")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            if sessions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars")
                        .font(.title3)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 40, height: 40)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 13)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Recovery day")
                            .font(.subheadline.weight(.semibold))

                        Text("Nothing is scheduled in \(plan.title) today.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, workout in
                        todayPlanRow(
                            workout,
                            planID: plan.id,
                            isHealthCompleted:
                                healthCompletedIDs.contains(workout.id),
                            isManuallyCompleted:
                                manuallyCompletedIDs.contains(workout.id),
                            isFirst: index == 0,
                            isLast: index == sessions.count - 1
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var noActivePlanCard: some View {
        ATHLTHCard {
            HStack(spacing: 10) {
                Text("Today's Plan")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    selectedSection = 2
                } label: {
                    HStack(spacing: 5) {
                        Text("Choose Plan")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 13) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("No active training plan")
                        .font(.subheadline.weight(.semibold))

                    Text("Start or create a program to see today's sessions, times and completed workouts here.")
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.top, 12)

            Button {
                selectedSection = 2
            } label: {
                Text("Explore Programs")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ATHLTHTheme.accentDeep)
            .background(
                ATHLTHTheme.accentSoft,
                in: RoundedRectangle(cornerRadius: 15)
            )
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func todayPlanRow(
        _ workout: PlannedSession,
        planID: UUID,
        isHealthCompleted: Bool,
        isManuallyCompleted: Bool,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        let isCompleted = isHealthCompleted || isManuallyCompleted

        Button {
            selectedPlanWorkout = PlannedWorkoutSelection(
                planID: planID,
                workout: workout,
                isHealthCompleted: isHealthCompleted
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if !isFirst {
                        Rectangle()
                            .fill(ATHLTHTheme.accent.opacity(0.16))
                            .frame(width: 2, height: 22)
                            .offset(y: -21)
                    }

                    if !isLast {
                        Rectangle()
                            .fill(ATHLTHTheme.accent.opacity(0.16))
                            .frame(width: 2, height: 22)
                            .offset(y: 21)
                    }

                    Circle()
                        .fill(
                            isCompleted
                                ? ATHLTHTheme.accent
                                : Color.white.opacity(0.94)
                        )
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .stroke(
                                    isCompleted
                                        ? ATHLTHTheme.accent
                                        : ATHLTHTheme.accent.opacity(0.42),
                                    lineWidth: 1.5
                                )
                        }

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 32, height: 58)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .lineLimit(1)

                    Text(todaySessionSummary(workout))
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(
                        todayPlanStatus(
                            workout,
                            isCompleted: isCompleted
                        )
                    )
                    .font(.caption.weight(isCompleted ? .semibold : .regular))
                    .foregroundStyle(
                        isCompleted
                            ? ATHLTHTheme.accent
                            : ATHLTHTheme.mutedText
                    )
                    .lineLimit(1)

                    if isHealthCompleted {
                        Label("Health", systemImage: "heart.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    } else if isManuallyCompleted {
                        Text("Manual")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 64)
            .background(
                Color.white.opacity(0.42),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .accessibilityLabel(
            "\(workout.title), \(isCompleted ? "completed" : "planned")"
        )
        .accessibilityHint("Open workout details")
    }

    private func todayPlanStatus(
        _ workout: PlannedSession,
        isCompleted: Bool
    ) -> String {
        if isCompleted {
            return "Completed"
        }

        if let scheduledStart = workout.scheduledStart {
            return scheduledStart.formatted(
                date: .omitted,
                time: .shortened
            )
        }

        return "Today"
    }

    private func manuallyCompletedTodaySessionIDs(
        planID: UUID,
        sessions: [PlannedSession]
    ) -> Set<UUID> {
        Set(
            sessions
                .filter {
                    session.isPlanSessionManuallyCompleted(
                        planID: planID,
                        sessionID: $0.id
                    )
                }
                .map(\.id)
        )
    }

    private func healthCompletedTodaySessionIDs(
        _ sessions: [PlannedSession]
    ) -> Set<UUID> {
        let calendar = Calendar.current
        var unusedWorkouts = health.workouts
            .filter { calendar.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }

        var result = Set<UUID>()

        for session in sessions {
            guard let matchIndex = unusedWorkouts.firstIndex(where: {
                healthWorkout($0, matches: session)
            }) else {
                continue
            }

            result.insert(session.id)
            unusedWorkouts.remove(at: matchIndex)
        }

        return result
    }

    private func healthWorkout(
        _ workout: WorkoutSummary,
        matches session: PlannedSession
    ) -> Bool {
        switch session.kind {
        case .running:
            return workout.activity == .running
        case .walking:
            return workout.activity == .walking || workout.activity == .hiking
        case .strength:
            return workout.activity == .strength
        case .mobility:
            return workout.activity == .yoga || workout.activity == .coreTraining
        case .recovery:
            return false
        case .custom:
            return workout.activity == .hiit ||
                workout.activity == .rowing ||
                workout.activity == .cycling ||
                workout.activity == .stairClimbing ||
                workout.activity == .other
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

    private func routeRegion(
        _ route: TrainingRoute
    ) -> MKCoordinateRegion? {
        let coordinates = route.coordinates.map(\.coordinate)
        guard let first = coordinates.first else {
            return nil
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max()
        else {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.01,
                    longitudeDelta: 0.01
                )
            )
        }

        let latitudeDelta = max(
            (maxLatitude - minLatitude) * 1.30,
            0.01
        )
        let longitudeDelta = max(
            (maxLongitude - minLongitude) * 1.30,
            0.01
        )

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }


}

struct ATHLTHRecoveryView: View {
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        NavigationStack {
            ATHLTHPinnedHeroLayout(
                accent: Color.blue.opacity(0.70)
            ) {
                ATHLTHTabHero(
                    imageName: "RecoveryHero",
                        title: "Recovery",
                        subtitle: "Use sleep and recovery signals to guide today's load.",
                        height: 190,
                        alignment: .leading,
                        focalOffsetX: 14,
                    focalOffsetY: 16
                )
            } content: {
                VStack(spacing: 16) {
                        if shouldShowWearableRecoveryContent {
                            recoveryScoreCard
                            todaysSignalsCard
                            todaysGuidanceCard
                            baselineCard
                            recoveryMethodCard
                        } else {
                            recoveryUnavailableCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                await health.refreshAll()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var recoveryScoreCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Recovery",
                actionTitle: "Today"
            )

            if let score = health.recovery.score {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 18) {
                        ATHLTHProgressRing(
                            title: health.recovery.state.title,
                            value: "\(score)",
                            progress: Double(score) / 100,
                            icon: health.recovery.state.systemImage,
                            tint: ATHLTHTheme.accent
                        )
                        .frame(width: 116)

                        recoveryScoreCopy
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ATHLTHProgressRing(
                            title: health.recovery.state.title,
                            value: "\(score)",
                            progress: Double(score) / 100,
                            icon: health.recovery.state.systemImage,
                            tint: ATHLTHTheme.accent
                        )
                        .frame(maxWidth: .infinity)

                        recoveryScoreCopy
                    }
                }
                .padding(.top, 10)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 50, height: 50)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Building your baseline")
                            .font(.headline)

                        Text(health.recovery.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
            }
        }
    }

    private var recoveryScoreCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recoveryHeadline)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(health.recovery.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var todaysSignalsCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: "Today's signals")

            HStack(alignment: .top, spacing: 0) {
                recoverySignalMetric(
                    title: "Sleep",
                    value: health.sleep.totalAsleep > 0
                        ? health.sleep.totalAsleep.shortDuration
                        : "—",
                    comparison: sleepComparisonText,
                    icon: "moon.fill",
                    tint: .purple
                )

                recoverySignalDivider

                recoverySignalMetric(
                    title: "HRV",
                    value: health.heart.hrvMilliseconds.map {
                        "\(Int($0.rounded())) ms"
                    } ?? "—",
                    comparison: hrvComparisonText,
                    icon: "waveform.path.ecg",
                    tint: .blue
                )

                recoverySignalDivider

                recoverySignalMetric(
                    title: "Resting HR",
                    value: health.heart.restingHeartRate.map {
                        "\(Int($0.rounded())) bpm"
                    } ?? "—",
                    comparison: restingHRComparisonText,
                    icon: "heart.fill",
                    tint: .red
                )
            }
            .padding(.top, 14)
        }
    }

    private var todaysGuidanceCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(title: "Today's guidance")

            HStack(alignment: .top, spacing: 13) {
                Image(systemName: health.recovery.state.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(guidanceTitle)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(guidanceDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 10)
        }
    }

    private var baselineCard: some View {
        ATHLTHCard {
            ATHLTHSectionHeader(
                title: "Baseline",
                actionTitle: health.recovery.baselineDays > 0
                    ? "\(health.recovery.baselineDays) days"
                    : nil
            )

            HStack(alignment: .top, spacing: 0) {
                baselineMetric(
                    title: "Sleep",
                    value: health.recovery.averageSleepDuration
                        .map(\.shortDuration) ?? "—"
                )

                recoverySignalDivider

                baselineMetric(
                    title: "HRV",
                    value: health.recovery.baselineHRVMilliseconds.map {
                        "\(Int($0.rounded())) ms"
                    } ?? "—"
                )

                recoverySignalDivider

                baselineMetric(
                    title: "Resting HR",
                    value: health.recovery.baselineRestingHeartRate.map {
                        "\(Int($0.rounded())) bpm"
                    } ?? "—"
                )
            }
            .padding(.top, 14)
        }
    }

    private var recoveryMethodCard: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("How ATHLTH calculates recovery")
                        .font(.subheadline.weight(.semibold))

                    Text(
                        "ATHLTH compares your recent sleep, HRV and resting heart rate with your own baseline. The score is a training-readiness signal, not a medical assessment."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var recoveryUnavailableCard: some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Recovery data isn’t available yet")
                        .font(.headline)

                    Text(recoveryUnavailableDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var recoverySignalDivider: some View {
        Rectangle()
            .fill(ATHLTHTheme.divider)
            .frame(width: 1, height: 94)
            .padding(.horizontal, 6)
    }

    private func recoverySignalMetric(
        title: String,
        value: String,
        comparison: String?,
        icon: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: 20)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(.numericText())

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(comparison ?? "No baseline yet")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func baselineMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var sleepComparisonText: String? {
        guard health.sleep.totalAsleep > 0,
              let baseline = health.recovery.averageSleepDuration,
              baseline > 0 else {
            return nil
        }

        return durationComparison(
            current: health.sleep.totalAsleep,
            baseline: baseline
        )
    }

    private var hrvComparisonText: String? {
        guard let current = health.heart.hrvMilliseconds,
              let baseline = health.recovery.baselineHRVMilliseconds else {
            return nil
        }

        return numberComparison(
            current: current,
            baseline: baseline,
            unit: "ms"
        )
    }

    private var restingHRComparisonText: String? {
        guard let current = health.heart.restingHeartRate,
              let baseline = health.recovery.baselineRestingHeartRate else {
            return nil
        }

        return numberComparison(
            current: current,
            baseline: baseline,
            unit: "bpm"
        )
    }

    private func durationComparison(
        current: TimeInterval,
        baseline: TimeInterval
    ) -> String {
        let difference = current - baseline

        guard abs(difference) >= 60 else {
            return "At baseline"
        }

        let totalMinutes = Int((abs(difference) / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let sign = difference > 0 ? "+" : "−"

        if hours > 0, minutes > 0 {
            return "\(sign)\(hours)h \(minutes)m vs baseline"
        }

        if hours > 0 {
            return "\(sign)\(hours)h vs baseline"
        }

        return "\(sign)\(minutes)m vs baseline"
    }

    private func numberComparison(
        current: Double,
        baseline: Double,
        unit: String
    ) -> String {
        let difference = Int((current - baseline).rounded())

        guard difference != 0 else {
            return "At baseline"
        }

        let sign = difference > 0 ? "+" : "−"
        return "\(sign)\(abs(difference)) \(unit) vs baseline"
    }

    private var shouldShowWearableRecoveryContent: Bool {
        health.recovery.score != nil ||
            health.sleep.totalAsleep > 0 ||
            health.heart.hrvMilliseconds != nil ||
            health.heart.restingHeartRate != nil ||
            health.recovery.baselineDays > 0
    }

    private var recoveryUnavailableDetail: String {
        if !health.hasRequestedAuthorization {
            switch settings.trainingDeviceProvider {
            case .appleWatch:
                return "Apple Watch health metrics stay hidden until setup is complete and Apple Health data is available. You can still use training plans, log strength sessions and use the rest of ATHLTH."
            case .garmin:
                return "Garmin health sync is not active yet and Apple Health is not connected, so ATHLTH hides unavailable recovery metrics."
            case .none:
                return "You selected No watch and Apple Health is not connected. ATHLTH keeps this page clean instead of showing empty wearable metrics. You can connect Apple Health or a wearable later in Settings."
            }
        }

        switch settings.trainingDeviceProvider {
        case .none:
            return "Apple Health is configured. ATHLTH will show recovery here when compatible readable sleep, HRV or resting heart-rate data becomes available; until then, empty wearable cards stay hidden."
        case .appleWatch:
            return "ATHLTH will show recovery as soon as compatible Apple Health data from your Watch or another source is available. Empty metrics stay hidden in the meantime."
        case .garmin:
            return "ATHLTH will show recovery when compatible Apple Health or future Garmin data becomes available."
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
}

private struct ATHLTHProgressHero: View {
    let title: String
    let subtitle: String
    var height: CGFloat = 190

    private var hasDedicatedProgressArtwork: Bool {
        guard let image = UIImage(named: "ProgressHero"),
              image.size.height > 0 else {
            return false
        }

        // The temporary/legacy duplicate is an ultra-wide 3:1 profile photo.
        // The intended Progress artwork is 16:9. Keep the fallback active until
        // the dedicated asset has actually been replaced.
        return image.size.width / image.size.height < 2.2
    }

    @ViewBuilder
    var body: some View {
        if hasDedicatedProgressArtwork {
            ATHLTHTabHero(
                imageName: "ProgressHero",
                title: title,
                subtitle: subtitle,
                height: height,
                alignment: .leading,
                focalOffsetX: -12,
                focalOffsetY: 12
            )
        } else {
            ATHLTHProgressFallbackHero(
                title: title,
                subtitle: subtitle,
                height: height
            )
        }
    }
}

private struct ATHLTHProgressFallbackHero: View {
    let title: String
    let subtitle: String
    var height: CGFloat = 190

    private let sky = Color(red: 0.84, green: 0.92, blue: 0.98)
    private let warm = Color(red: 1.00, green: 0.95, blue: 0.86)
    private let stone = Color(red: 0.93, green: 0.90, blue: 0.84)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [sky, Color.white, warm],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )

                scenicBackdrop(proxy: proxy)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        Color.white.opacity(0.72),
                        Color.white.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 0) {
                    heroCopy
                        .frame(
                            width: min(proxy.size.width * 0.47, 360),
                            alignment: .leading
                        )

                    Spacer(minLength: 4)

                    metricsArtwork
                        .frame(
                            width: max(proxy.size.width * 0.51, 190),
                            alignment: .trailing
                        )
                        .offset(y: 13)
                }
                .padding(.horizontal, 18)
                .padding(.top, 43)
                .padding(.bottom, 14)
            }
            .clipped()
        }
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    @ViewBuilder
    private func scenicBackdrop(
        proxy: GeometryProxy
    ) -> some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color(red: 0.63, green: 0.72, blue: 0.78).opacity(0.24))
                .frame(
                    width: proxy.size.width * 0.84,
                    height: proxy.size.height * 0.58
                )
                .offset(
                    x: proxy.size.width * 0.20,
                    y: proxy.size.height * 0.26
                )

            Ellipse()
                .fill(Color(red: 0.49, green: 0.60, blue: 0.66).opacity(0.16))
                .frame(
                    width: proxy.size.width * 0.68,
                    height: proxy.size.height * 0.45
                )
                .offset(
                    x: proxy.size.width * 0.31,
                    y: proxy.size.height * 0.31
                )

            LinearGradient(
                colors: [
                    Color(red: 0.58, green: 0.76, blue: 0.86).opacity(0.34),
                    Color.white.opacity(0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: proxy.size.height * 0.42)
            .offset(y: proxy.size.height * 0.13)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            stone.opacity(0.90),
                            Color.white.opacity(0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(
                    width: proxy.size.width * 0.72,
                    height: proxy.size.height * 0.31
                )
                .offset(
                    x: proxy.size.width * 0.24,
                    y: proxy.size.height * 0.18
                )
                .shadow(
                    color: Color.black.opacity(0.06),
                    radius: 16,
                    x: 0,
                    y: 8
                )
        }
        .allowsHitTesting(false)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ATHLTH")
                .font(.system(size: 17, weight: .black))
                .tracking(5.5)

            Text("MOVE BETTER · LIVE LONGER")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.7)
                .padding(.top, 2)

            Spacer(minLength: 10)

            Text(title)
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1)

            Text(subtitle)
                .font(.subheadline)
                .lineLimit(2)
                .padding(.top, 2)
        }
        .foregroundStyle(ATHLTHTheme.primaryText)
        .shadow(color: .white.opacity(0.46), radius: 3)
    }

    private var metricsArtwork: some View {
        HStack(spacing: 6) {
            progressMetricPanel(
                title: "Workouts",
                value: "12",
                detail: "THIS WEEK",
                tint: .blue,
                icon: "dumbbell.fill"
            )

            progressMetricPanel(
                title: "Activity",
                value: "4.2k",
                detail: "ACTIVE",
                tint: .green,
                icon: "bolt.fill"
            )

            progressMetricPanel(
                title: "Steps",
                value: "8.4k",
                detail: "DAILY AVG",
                tint: .cyan,
                icon: "figure.walk"
            )

            progressMetricPanel(
                title: "Recovery",
                value: "78%",
                detail: "SCORE",
                tint: .purple,
                icon: "leaf.fill"
            )
        }
        .scaleEffect(0.92, anchor: .trailing)
    }

    private func progressMetricPanel(
        title: String,
        value: String,
        detail: String,
        tint: Color,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            Spacer(minLength: 2)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)

            Text(detail)
                .font(.system(size: 6.5, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)

            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(tint.opacity(0.25 + Double(index) * 0.15))
                        .frame(
                            width: 3,
                            height: CGFloat(5 + index * 3)
                        )
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
        .padding(8)
        .frame(width: 62, height: 102, alignment: .leading)
        .background(
            Color.white.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 9,
            x: 0,
            y: 5
        )
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
            ATHLTHPinnedHeroLayout(
                accent: green.opacity(0.60)
            ) {
                ATHLTHProgressHero(
                    title: "Progress",
                        subtitle: "See your training, consistency and health trends.",
                    height: 190
                )
            } content: {
                VStack(spacing: 14) {
                    if health.hasRequestedAuthorization &&
                        (health.hasTrainingHealthData || progressHasHealthData) {
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
                    } else {
                        progressWithoutHealthCard

                        HStack(alignment: .top, spacing: 12) {
                            personalRecordsCard
                            achievementsCard
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
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

    private var progressWithoutHealthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(green)
                    .frame(width: 48, height: 48)
                    .background(
                        green.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        health.hasRequestedAuthorization
                            ? "No Apple Health progress data yet"
                            : "Progress without Apple Health"
                    )
                    .font(.headline)

                    Text(
                        health.hasRequestedAuthorization
                            ? "Apple Health is configured, but ATHLTH has not found readable workout, steps or sleep progress for this period yet. Health-based charts stay hidden instead of showing empty cards."
                            : "Health-based charts stay hidden until Apple Health is connected. Strength records, goals, achievements and other ATHLTH-native progress remain available."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .progressReferenceCard()
    }

    private var progressHasHealthData: Bool {
        guard let snapshot = progressSnapshot else { return false }

        return snapshot.workoutCount > 0 ||
            (snapshot.totalSteps ?? 0) > 0 ||
            (snapshot.averageSleepDuration ?? 0) > 0 ||
            snapshot.trainingDuration > 0
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
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    ATHLTHTheme.cardWarm.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    ATHLTHTheme.premiumGold.opacity(0.12),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: ATHLTHTheme.accentDeep.opacity(0.07),
            radius: 12,
            x: 0,
            y: 6
        )
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
                    icon: health.recovery.state.systemImage,
                    tint: green,
                    value: health.recovery.score.map { String($0) } ?? "—",
                    title: "Recovery",
                    change: nil,
                    footer: health.recovery.score == nil
                        ? health.recovery.state.title
                        : "ATHLTH score"
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
    @EnvironmentObject private var gear: ProfileGearStore

    @State private var performanceStats: ProfilePerformanceStats?
    @State private var performanceStatsLoading = false

    var body: some View {
        ATHLTHPinnedHeroLayout(
            accent: ATHLTHTheme.premiumGold.opacity(0.62)
        ) {
            profileHero
        } content: {
            VStack(spacing: 16) {
                profileSocialStatsCard
                trainingIdentityCard
                ProfileGearSummaryView()

                WorkoutHistoryPreviewSection()

                goalsAndTrophies

                if settings.showPerformanceStatsOnProfile {
                    ProfilePerformanceSection(
                        stats: performanceStats,
                        isLoading: performanceStatsLoading
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 120)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable {
            await refreshProfile(forceRefresh: true)
        }
        .task {
            await refreshProfile()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ATHLTHSettingsView()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                        .frame(width: 40, height: 40)
                        .background(
                            ATHLTHTheme.cardWarm.opacity(0.82),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.80), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    private var profileHero: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        ATHLTHTheme.cardWarm,
                        ATHLTHTheme.surfaceSage,
                        ATHLTHTheme.canvasBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        ATHLTHTheme.premiumGold.opacity(0.24),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(proxy.size.width * 0.70, 260)
                )

                RadialGradient(
                    colors: [
                        ATHLTHTheme.vitality.opacity(0.16),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: max(proxy.size.width * 0.56, 220)
                )

                HStack(alignment: .center, spacing: 16) {
                    profileAvatar

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PROFILE")
                            .font(.caption2.weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(
                                ATHLTHTheme.accentDeep.opacity(0.62)
                            )

                        Text(session.profile.displayName)
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.76)

                        Text("@\(session.profile.username)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.mutedText)

                        if !session.profile.bio
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty {
                            Text(session.profile.bio)
                                .font(.caption)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText.opacity(0.72)
                                )
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 6)

                    NavigationLink {
                        ATHLTHEditProfileView()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.74),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit Profile")
                }
                .padding(.horizontal, 20)
                .padding(.top, 62)
                .padding(.bottom, 24)
            }
        }
        .frame(height: 230)
        .clipped()
    }

    private var profileSocialStatsCard: some View {
        ATHLTHCard {
            HStack(spacing: 0) {
                NavigationLink {
                    ProfileFollowListView(mode: .followers)
                } label: {
                    socialStat(
                        value: social.followerCount,
                        title: "Followers",
                        icon: "person.2.fill"
                    )
                }
                .buttonStyle(.plain)

                profileStatDivider

                NavigationLink {
                    ProfileFollowListView(mode: .following)
                } label: {
                    socialStat(
                        value: social.followingCount,
                        title: "Following",
                        icon: "person.badge.plus"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trainingIdentityCard: some View {
        ATHLTHCard {
            HStack {
                Text("Training Identity")
                    .font(.title3.weight(.bold))

                Spacer()

                NavigationLink {
                    ATHLTHEditProfileView()
                } label: {
                    HStack(spacing: 5) {
                        Text("Edit")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                }
                .buttonStyle(.plain)
            }

            if identityFocuses.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(ATHLTHTheme.accent)
                    Text("Choose your training identity in Edit Profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 12)
            } else {
                HStack(spacing: 9) {
                    ForEach(identityFocuses) { focus in
                        Label(focus.title, systemImage: focus.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(identityTint(focus))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(
                                identityTint(focus).opacity(0.09),
                                in: Capsule()
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private var goalsAndTrophies: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                goalsCard
                trophiesCard
            }

            VStack(spacing: 12) {
                goalsCard
                trophiesCard
            }
        }
    }

    private var goalsCard: some View {
        Group {
            if let goal = goalStore.primaryGoal {
                NavigationLink {
                    GoalDetailView(goalID: goal.id)
                } label: {
                    ATHLTHCard {
                        HStack(spacing: 12) {
                            Image(systemName: "target")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.green)
                                .frame(width: 44, height: 44)
                                .background(
                                    Color.green.opacity(0.10),
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Goals")
                                    .font(.headline)
                                    .foregroundStyle(ATHLTHTheme.primaryText)

                                Text(goal.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ATHLTHTheme.primaryText)
                                    .lineLimit(1)

                                Text("\(Int((goal.progress * 100).rounded()))% complete")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }

                        ProgressView(value: goal.progress)
                            .tint(.green)
                            .padding(.top, 8)
                    }
                }
                .buttonStyle(.plain)
            } else {
                ATHLTHCard {
                    HStack(spacing: 12) {
                        Image(systemName: "target")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.green)
                            .frame(width: 44, height: 44)
                            .background(Color.green.opacity(0.10), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Goals")
                                .font(.headline)
                            Text("No active goal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var trophiesCard: some View {
        NavigationLink {
            TrophyCollectionView()
        } label: {
            ATHLTHCard {
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 44, height: 44)
                        .background(
                            Color.orange.opacity(0.10),
                            in: Circle()
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Trophies")
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text("\(trophyStore.unlockedCount)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text("Unlocked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var identityFocuses: [TrainingFocus] {
        guard let focus = session.onboardingProfile?.trainingFocus else {
            return []
        }

        if focus == .hybrid {
            return [.running, .strength, .hybrid]
        }

        return [focus]
    }

    private func identityTint(_ focus: TrainingFocus) -> Color {
        switch focus {
        case .running: return .green
        case .strength: return .purple
        case .hybrid: return .orange
        case .walking: return .blue
        case .generalFitness: return ATHLTHTheme.accent
        case .recovery: return .teal
        }
    }

    private var profileStatDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.07))
            .frame(width: 1, height: 42)
    }

    private func socialStat(
        value: Int,
        title: String,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.mutedText)

            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted())
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
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
                    avatarFallback
                }
            }
            .frame(width: 104, height: 104)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.95), lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
        } else {
            avatarFallback
                .frame(width: 104, height: 104)
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(ATHLTHTheme.accentSoft)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
            }
    }

    @MainActor
    private func refreshProfile(forceRefresh: Bool = false) async {
        async let socialRefresh: Void = social.refresh()
        async let gearRefresh: Void = gear.refresh()

        if health.hasRequestedAuthorization {
            performanceStatsLoading = true
            performanceStats = try? await health.profilePerformanceStats(
                forceRefresh: forceRefresh
            )
            performanceStatsLoading = false
        } else {
            performanceStats = nil
        }

        _ = await (socialRefresh, gearRefresh)

        if social.privacy?.sharePerformanceStats == true {
            await social.syncOwnPerformance(performanceStats)
        }
        if social.privacy?.shareTrophyCabinet == true {
            await social.syncOwnTrophies(trophyStore.showcaseTrophies)
        }
    }
}
