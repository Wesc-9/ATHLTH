import SwiftUI
import Charts

/// Keep seven existing calendar cards fully visible on wide iPads and allow
/// horizontal scrolling only in compact Stage Manager windows.
enum ATHLTHStudioWeekTileLayout {
    static func tileWidth(
        viewport: CGFloat,
        accessibilityText: Bool
    ) -> CGFloat {
        let usable = min(max(0, viewport), 1500)
        let outerInset: CGFloat =
            usable >= 730 && !accessibilityText ? 44 : 28
        return max(88, (usable - outerInset - 40 - 6 * 8) / 7)
    }
}

/// No day is complete just because its first planned workout is done.
enum ATHLTHStudioDayCompletionPolicy {
    /// Stable partition: never reorder workouts within their original group.
    static func partition<Item>(
        _ items: [Item], isFinished: (Item) -> Bool
    ) -> (pending: [Item], finished: [Item]) {
        var pending: [Item] = []
        var finished: [Item] = []
        for item in items {
            if isFinished(item) { finished.append(item) }
            else { pending.append(item) }
        }
        return (pending, finished)
    }

    static func allPlannedCompleted<Item>(
        _ items: [Item],
        isCompleted: (Item) -> Bool
    ) -> Bool {
        !items.isEmpty && items.allSatisfy(isCompleted)
    }
}

enum ATHLTHStudioDayWorkoutLayout {
    static func contentWidth(viewport: CGFloat, accessibilityText: Bool) -> CGFloat {
        let outerInset: CGFloat = viewport >= 730 && !accessibilityText ? 44 : 28
        return max(0, min(1500, viewport - outerInset) - 40)
    }

    static func columns(contentWidth: CGFloat, count: Int, accessibilityText: Bool) -> Int {
        count > 1 && contentWidth >= 780 && !accessibilityText ? 2 : 1
    }
}

/// Recommendation derived only from observed workout categories and saved plans.
/// No synthetic readiness, medical claims or inferred completion.
enum ATHLTHStudioHomeRecommendation {
    struct Result {
        let titleEnglish: String
        let titleNorwegian: String
        let reasonEnglish: String
        let reasonNorwegian: String
    }

    static func make(
        nextWorkoutTitle: String?,
        workouts: [WorkoutSummary],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Result {
        if let title = nextWorkoutTitle, !title.isEmpty {
            return Result(
                titleEnglish: title,
                titleNorwegian: title,
                reasonEnglish: "You already have a workout scheduled. Review your plan before starting.",
                reasonNorwegian: "Du har allerede en planlagt økt. Se gjennom planen før du starter."
            )
        }
        let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        var recentCount = 0
        var strengthCount = 0
        var runCount = 0
        for workout in workouts where workout.startDate >= start &&
            workout.startDate <= now {
            recentCount += 1
            if workout.activity == .strength { strengthCount += 1 }
            if workout.activity == .running { runCount += 1 }
        }
        if recentCount == 0 {
            return Result(
                titleEnglish: "Start with a workout that suits you",
                titleNorwegian: "Velg en økt som passer deg",
                reasonEnglish: "No recent workout history is available. Pick a comfortable starting point.",
                reasonNorwegian: "Ingen nylig treningshistorikk er tilgjengelig. Velg en passende start."
            )
        }
        if strengthCount == 0 && runCount > 0 {
            return Result(
                titleEnglish: "Consider a strength session",
                titleNorwegian: "Vurder en styrkeøkt",
                reasonEnglish: "You have recorded running but no strength training in the last seven days.",
                reasonNorwegian: "Du har registrert løping, men ingen styrkeøkt de siste sju dagene."
            )
        }
        if runCount == 0 && strengthCount > 0 {
            return Result(
                titleEnglish: "Consider an easy walk or run",
                titleNorwegian: "Vurder en rolig tur eller løpetur",
                reasonEnglish: "You have recorded strength training but no running in the last seven days.",
                reasonNorwegian: "Du har registrert styrketrening, men ingen løping de siste sju dagene."
            )
        }
        return Result(
            titleEnglish: "Choose based on how you feel today",
            titleNorwegian: "Velg etter dagsformen",
            reasonEnglish: "Your recent training is recorded. Adjust the next session to your energy and goals.",
            reasonNorwegian: "Nylig trening er registrert. Tilpass neste økt til energi og mål."
        )
    }
}

/// A stable account-scoped projection is derived only when its source data
/// changes. SwiftUI rendering, the live workout heartbeat and sidebar
/// navigation can then reuse the same calendar/history/chart model.
private struct ATHLTHStudioHomeProjection {
    let accountID: UUID
    let selectedWeekDate: Date
    let analyticsPeriodDays: Int
    let workouts: [WorkoutSummary]
    let week: ATHLTHStudioHomeWeek.Snapshot
    let upcoming: [ATHLTHStudioSchedule.Occurrence]
    let analytics: ATHLTHStudioAnalytics.Snapshot
    let completedByPlanSession: [String: Bool]
}

/// iPad-only Studio home, inspired by the approved airy ATHLTH Studio reference.
/// The content is sourced from existing local session and Health stores; no
/// demonstration values, artificial readiness scores or implicit completions.
struct ATHLTHStudioEditorialDashboardView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var studioPlanSync: ATHLTHStudioPlanSyncStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    let onInspect: (WorkoutSummary) -> Void
    let onOpenPlanner: () -> Void
    let onOpenPlanSync: () -> Void
    let onOpenInsights: () -> Void
    let onOpenSettings: () -> Void
    let onOpenCommunity: (ATHLTHCommunityMainTab) -> Void
    let onOpenTrainTogether: () -> Void
    let onOpenNotifications: () -> Void
    let onOpenWorkout: (ATHLTHStudioSchedule.Occurrence) -> Void
    let onStartWorkout: (ATHLTHStudioSchedule.Occurrence) -> Void
    let onSendToWatch: (ATHLTHStudioSchedule.Occurrence) -> Void
    let onStartAfter: (ATHLTHStudioSchedule.Occurrence, TimeInterval) -> Void
    @Binding var focusedPlanningDate: Date?

    @Binding var selectedDate: Date
    let scrollToTopRequest: Int
    @State private var periodDays = 28
    /// Each iPad scene remembers whether the athlete deliberately browsed
    /// a different week; reopening must not silently jump back to today.
    @SceneStorage("athlth.studio.homeFollowsToday") private var followsToday = true
    @State private var showingReadinessExplanation = false
    @State private var homeProjection: ATHLTHStudioHomeProjection?
    @State private var pendingProjectionTask: Task<Void, Never>?

    private let cream = Color(red: 0.984, green: 0.978, blue: 0.966)
    private let ink = Color(red: 0.18, green: 0.17, blue: 0.16)
    private let bronze = Color(red: 0.62, green: 0.47, blue: 0.29)
    private let outline = Color(red: 0.90, green: 0.88, blue: 0.84)

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var hasHealth: Bool {
        health.healthDataAvailable && health.hasRequestedAuthorization
    }

    private var recordedWorkouts: [WorkoutSummary] {
        ATHLTHStudioRecordedWorkouts.merged(
            health: hasHealth ? health.workouts : [],
            localStrength: strength.workoutHistory
        )
    }

    private var program: TrainingPlan? {
        // Offline-first account data can include plans that are not yet on
        // the server. Only consider plans belonging to the signed-in user.
        guard session.signedIn else { return nil }
        if let active = session.activePlan,
           active.ownerID == session.profile.userID,
           !session.pausedTrainingPlanIDs.contains(active.id),
           !session.deactivatedTrainingPlanIDs.contains(active.id),
           session.trainingPlanStatus(active) == .active {
            return active
        }
        guard let upcoming = session.nextTrainingPlan,
              upcoming.ownerID == session.profile.userID else { return nil }
        return upcoming
    }

    private var programStatus: TrainingPlanTimingStatus? {
        program.map { session.trainingPlanStatus($0) }
    }

    private var planSyncHint: String? {
        guard let plan = program else { return nil }
        if !studioPlanSync.enabled {
            return tr("Saved on this device · account sync is off",
                      "Lagret på denne enheten · kontosynkronisering er av")
        }
        guard let remoteIDs = studioPlanSync.verifiedRemotePlanIDs else {
            return tr("Saved on this device · account sync not confirmed",
                      "Lagret på denne enheten · kontosynkronisering ikke bekreftet")
        }
        guard !remoteIDs.contains(plan.id) else { return nil }
        return tr("Only on this device · not in your account yet",
                  "Kun på denne enheten · ikke på kontoen ennå")
    }

    private func nextWorkout(
        from upcoming: [ATHLTHStudioSchedule.Occurrence]
    ) -> ATHLTHStudioSchedule.Occurrence? {
        upcoming.first { item in
            guard ATHLTHStudioSchedule.isUpcoming(item) else { return false }
            return !skipped(item) && !completed(item) && !item.workout.isExplicitRestDay
        }
    }

    private func makeHomeProjection() -> ATHLTHStudioHomeProjection {
        let workouts = recordedWorkouts
        let plans = session.trainingPlans
        let windows = ATHLTHStudioSchedule.studioHomeWindows(
            plans: plans,
            standalone: session.standalonePlannedSessions,
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            selectedWeekDate: selectedDate
        )
        let week = ATHLTHStudioHomeWeek.make(
            plans: plans,
            standalone: session.standalonePlannedSessions,
            recorded: workouts,
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            now: selectedDate,
            plannedOverride: windows.week
        )
        // A plan completion can inspect stored structured-workout progress.
        // Resolve each plan/session only once per source update rather than
        // once for each of its day tile, summary and featured workout.
        var completedByPlanSession: [String: Bool] = [:]
        for item in windows.week + windows.upcoming {
            guard let planID = item.planID else { continue }
            let key = "\(planID.uuidString):\(item.workout.id.uuidString)"
            if completedByPlanSession[key] == nil {
                completedByPlanSession[key] = session.isPlanSessionCompleted(
                    planID: planID, sessionID: item.workout.id,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                )
            }
        }
        return ATHLTHStudioHomeProjection(
            accountID: session.profile.userID,
            selectedWeekDate: selectedDate,
            analyticsPeriodDays: periodDays,
            workouts: workouts,
            week: week,
            upcoming: windows.upcoming,
            analytics: ATHLTHStudioAnalytics.snapshot(
                from: workouts, days: periodDays
            ),
            completedByPlanSession: completedByPlanSession
        )
    }

    private var currentHomeProjection: ATHLTHStudioHomeProjection {
        if let cached = homeProjection,
           cached.accountID == session.profile.userID,
           cached.selectedWeekDate == selectedDate,
           cached.analyticsPeriodDays == periodDays,
           session.signedIn {
            return cached
        }
        return makeHomeProjection()
    }

    private func scheduleProjectionRefresh() {
        pendingProjectionTask?.cancel()
        pendingProjectionTask = Task { @MainActor in
            // Coalesce HealthKit and plan-store publications from one save.
            // Avoid recalculating the calendar on every live heartbeat.
            do { try await Task.sleep(for: .milliseconds(80)) }
            catch { return }
            guard !Task.isCancelled else { return }
            homeProjection = makeHomeProjection()
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if let focusedPlanningDate {
                ATHLTHStudioFocusedWeekPlannerView(
                    initialDate: focusedPlanningDate,
                    onClose: { self.focusedPlanningDate = nil }
                )
            } else {
                // A single render pass shares one merged workout history and
                // week projection across the calendar and summary/chart.
                // New Health/local data automatically triggers a fresh pass.
                let home = currentHomeProjection
                let workouts = home.workouts
                let week = home.week
                let width = geometry.size.width
                let split = width >= 730 && !dynamicTypeSize.isAccessibilitySize

                // Keep the mountain hero fixed while the cards scroll in
                // their own content area. The existing plan button stays live.
                VStack(spacing: 0) {
                    mountainPlanHero
                        .frame(maxWidth: .infinity)
                        .frame(height: program == nil ? 290 : (split ? 344 : 308))

                    ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: split ? 20 : 16) {
                            // This is the actual signed-in iPad Home, not the
                            // legacy dashboard. Keep cross-device discovery
                            // above the large next-workout and analytics cards.
                            // The child observes live state independently,
                            // avoiding rebuilding the full training dashboard
                            // for every four-second spectator heartbeat.
                            ATHLTHiPadLiveWorkoutStatusCard()
                            let upcoming = nextWorkout(from: home.upcoming)

                            if split {
                                HStack(alignment: .top, spacing: 18) {
                                    nextWorkoutCard(
                                        upcoming,
                                        availableWidth: max(300, width - 44 - 18 -
                                            min(390, max(310, width * 0.30)) - 36)
                                    )
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    compactReadinessCard
                                        .frame(width: min(390, max(310, width * 0.30)))
                                }
                            } else {
                                nextWorkoutCard(upcoming, availableWidth: max(280, width - 64))
                                compactReadinessCard
                            }

                            weekCard(week, width: width)
                            progressCard(wide: split, data: home.analytics, week: week)
                            ATHLTHStudioHomeCommunitySummary(
                                onOpenCommunity: onOpenCommunity,
                                onOpenTrainTogether: onOpenTrainTogether,
                                onOpenNotifications: onOpenNotifications
                            )
                        }
                        .padding(.horizontal, split ? 22 : 14)
                        .padding(.vertical, 17)
                        .frame(maxWidth: 1500)
                        .frame(maxWidth: .infinity)
                        .id("athlth-studio-home-top")
                    }
                    .scrollIndicators(.hidden)
                    .background(cream)
                    .onChange(of: scrollToTopRequest) { _, _ in
                        withAnimation(.easeOut(duration: 0.20)) {
                            scrollProxy.scrollTo("athlth-studio-home-top", anchor: .top)
                        }
                    }
                    }
                }
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .background(cream.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if followsToday, focusedPlanningDate == nil {
                selectedDate = .now
            }
            // The 7/28/90-day chart is relative to today even when the
            // selected calendar week is historical.
            scheduleProjectionRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSCalendarDayChanged
        )) { _ in
            if followsToday, focusedPlanningDate == nil {
                selectedDate = .now
            }
            scheduleProjectionRefresh()
        }
        .task(id: session.profile.userID) {
            scheduleProjectionRefresh()
        }
        .onReceive(health.$workouts) { _ in
            scheduleProjectionRefresh()
        }
        .onReceive(strength.$workoutHistory) { _ in
            scheduleProjectionRefresh()
        }
        .onReceive(session.$activePlan) { _ in
            scheduleProjectionRefresh()
        }
        .onReceive(session.$scheduledPlans) { _ in
            scheduleProjectionRefresh()
        }
        .onReceive(session.$standalonePlannedSessions) { _ in
            scheduleProjectionRefresh()
        }
        .onReceive(session.$pausedTrainingPlanIDs) { _ in
            scheduleProjectionRefresh()
        }
        .onReceive(session.$deactivatedTrainingPlanIDs) { _ in
            scheduleProjectionRefresh()
        }
        .onReceive(session.$manuallyCompletedPlanSessions) { _ in
            scheduleProjectionRefresh()
        }
        .onReceive(session.$skippedPlanSessions) { _ in
            scheduleProjectionRefresh()
        }
        .onReceive(session.$linkedHealthWorkoutsByPlanSession) { _ in
            scheduleProjectionRefresh()
        }
        .onChange(of: selectedDate) { _, _ in
            scheduleProjectionRefresh()
        }
        .onChange(of: periodDays) { _, _ in
            scheduleProjectionRefresh()
        }
        .onChange(of: hasHealth) { _, _ in
            scheduleProjectionRefresh()
        }
        .onChange(of: session.signedIn) { _, _ in
            homeProjection = nil
            scheduleProjectionRefresh()
        }
        .onDisappear {
            pendingProjectionTask?.cancel()
        }
        .sheet(isPresented: $showingReadinessExplanation) {
            ATHLTHReadinessExplanationSheet(
                recovery: health.recovery,
                sleep: health.sleep,
                heart: health.heart
            )
        }
    }

    /// Full-bleed premium plan banner. Render real plan details over an
    /// existing bundled mountain photograph; no static plan text in the image.
    /// The rest of Studio Home retains its established cards and interactions.
    private var mountainPlanHero: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Image("StudioMountainSunrise")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.44),
                                Color.black.opacity(0.23),
                                Color.black.opacity(0.08),
                                Color.black.opacity(0.02)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.12),
                                .clear,
                                Color.black.opacity(0.30)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 11) {
                    Text("A T H L T H")
                        .font(.caption.weight(.semibold))
                        .tracking(2.6)
                        .foregroundStyle(Color(red: 0.88, green: 0.70, blue: 0.43))

                    Text(tr("Your training plan", "Din treningsplan"))
                        .font(.system(size: geometry.size.width < 620 ? 33 : 47,
                                      weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.76)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.2), radius: 4)

                    Rectangle()
                        .fill(Color(red: 0.83, green: 0.64, blue: 0.36))
                        .frame(width: 55, height: 3)
                        .padding(.top, 1)

                    Spacer(minLength: 8)

                    HStack(alignment: .bottom, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ATHLTHStudioHomePlanHeroPolicy.statusLabel(
                                for: programStatus,
                                norwegian: ATHLTHLocalization.isNorwegian
                            ))
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.3)
                                .foregroundStyle(.white.opacity(0.86))

                            Text(program?.title ??
                                 tr("Create your training plan", "Lag treningsplanen din"))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)

                            if let plan = program {
                                Text(weekLabel(plan))
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.90))
                            }
                            if let planSyncHint {
                                Button(action: onOpenPlanSync) {
                                    Label(planSyncHint, systemImage: "icloud.slash")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(tr(
                                    "Review account plan synchronization",
                                    "Kontroller kontosynkronisering av treningsplaner"
                                ))
                                .accessibilityIdentifier("athlth-ipad-plan-sync-warning")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: onOpenPlanner) {
                            HStack(spacing: 8) {
                                Text(program == nil
                                    ? tr("Create plan", "Opprett plan")
                                    : tr("View plan", "Se planen"))
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 17)
                            .frame(minHeight: 44)
                            .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("athlth-ipad-hero-open-plan")
                    }
                }
                .padding(.leading, geometry.size.width < 620 ? 23 : 42)
                .padding(.trailing, 26)
                // Content stays clear of status bar and the native Studio
                // navigation buttons overlaid on the edge-to-edge photograph.
                .padding(.top, 87)
                .padding(.bottom, 33)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityIdentifier("athlth-ipad-full-bleed-plan-hero")
    }

    private func nextWorkoutCard(
        _ next: ATHLTHStudioSchedule.Occurrence?,
        availableWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Text(tr("Next workout", "Neste økt"))
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                Spacer(minLength: 8)
                if let next {
                    Text(next.date.formatted(
                        .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bronze)
                }
            }
            if let item = next {
                ATHLTHStudioPlannedWorkoutHeroCard(
                    workout: item.workout,
                    availableWidth: availableWidth,
                    isCompleted: completed(item),
                    isSkipped: item.planID.map {
                        session.isPlanSessionSkipped(
                            planID: $0, sessionID: item.workout.id
                        )
                    } ?? false,
                    canStart: canStart(item),
                    onOpen: { onOpenWorkout(item) },
                    onStart: { onStartWorkout(item) }
                )
                .contextMenu { workoutActions(item) }
            } else {
                Text(
                    session.trainingPlans.isEmpty &&
                    session.standalonePlannedSessions.isEmpty
                        ? tr("Plan a workout to see it here.",
                             "Planlegg en økt for å se den her.")
                        : tr("No scheduled workouts in the next 14 days.",
                             "Ingen planlagte økter de neste 14 dagene.")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // The week calendar already offers planning; avoid a duplicate
                // call to action in the compact, empty next-session card.
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 222, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(outline.opacity(0.45), lineWidth: 0.6))
        .accessibilityIdentifier("athlth-ipad-next-workout")
    }

    private func weekCard(_ week: ATHLTHStudioHomeWeek.Snapshot,
                          width: CGFloat) -> some View {
        let activeDay = week.days.first {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        } ?? week.days.first
        let tileWidth = ATHLTHStudioWeekTileLayout.tileWidth(
            viewport: width,
            accessibilityText: dynamicTypeSize.isAccessibilitySize
        )

        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Your week", "Din treningsuke"))
                        .font(.system(size: 23, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                    let range = ATHLTHStudioHomeWeek.weekRange(containing: selectedDate)
                    Text(range.start.formatted(.dateTime.day().month(.abbreviated)) +
                         " – " +
                         range.end.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { shiftWeek(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 34, height: 34)
                }
                .accessibilityLabel(tr("Previous week", "Forrige uke"))
                Button {
                    followsToday = true
                    selectedDate = .now
                } label: {
                    Text(tr("Today", "I dag"))
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityLabel(tr("Go to current week", "Gå til denne uken"))
                Button { shiftWeek(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 34, height: 34)
                }
                .accessibilityLabel(tr("Next week", "Neste uke"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(ink)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(week.days) { day in
                        dayTile(day, selected: activeDay.map {
                            Calendar.current.isDate(day.date, inSameDayAs: $0.date)
                        } ?? false)
                        .frame(width: tileWidth)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Rectangle()
                .fill(outline)
                .frame(height: 1)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: activeDay?.restDays.isEmpty == false
                      ? "moon.zzz" : "calendar.badge.clock")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(bronze)
                    .frame(width: 42, height: 42)
                    .background(cream, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(weekSelectionSummary(activeDay))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ink)
                        .accessibilityAddTraits(.isHeader)
                    if let activeDay {
                        Text(activeDay.date.formatted(
                            .dateTime.weekday(.wide).day().month(.wide)
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let activeDay, activeDay.restDays.isEmpty,
                   HomeWeeklyProgressCalendar.canScheduleStandalone(
                       on: activeDay.date
                   ) {
                    Button {
                        focusedPlanningDate = activeDay.date
                    } label: {
                        Label(tr("Plan workout", "Planlegg økt"),
                              systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(bronze)
                    .accessibilityIdentifier("athlth-ipad-week-plan-selected-day")
                }
            }

            if let activeDay,
               !activeDay.planned.isEmpty || !activeDay.recorded.isEmpty {
                selectedDayWorkouts(activeDay, availableWidth: width)
                    .accessibilityIdentifier("athlth-ipad-selected-week-day-details")
            } else if let activeDay, !activeDay.restDays.isEmpty {
                Label(tr("Planned rest day", "Planlagt hviledag"),
                      systemImage: "moon.zzz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                Label(tr("No workout scheduled", "Ingen økt planlagt"),
                      systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }

            if !hasHealth {
                Button(action: onOpenSettings) {
                    Label(
                        tr(
                            "Apple Health is not connected. Planned workouts remain visible.",
                            "Apple Health er ikke tilkoblet. Planlagte økter vises fortsatt."
                        ),
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("athlth-ipad-health-source-status")
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline.opacity(0.45), lineWidth: 0.6))
        .accessibilityIdentifier("athlth-ipad-weekly-overview")
    }

    /// Equal cards for pending sessions, compact text rows for completed
    /// sessions and actual recordings. Do not infer a plan completion from
    /// an unrelated Health workout on the same date.
    private func selectedDayWorkouts(
        _ day: ATHLTHStudioHomeWeek.Day, availableWidth: CGFloat
    ) -> some View {
        let grouped = ATHLTHStudioDayCompletionPolicy.partition(day.planned) {
            completed($0) || skipped($0)
        }
        let contentWidth = ATHLTHStudioDayWorkoutLayout.contentWidth(
            viewport: availableWidth, accessibilityText: dynamicTypeSize.isAccessibilitySize)
        let columns = ATHLTHStudioDayWorkoutLayout.columns(
            contentWidth: contentWidth, count: grouped.pending.count,
            accessibilityText: dynamicTypeSize.isAccessibilitySize)
        let cardWidth = max(0, (contentWidth - CGFloat(columns - 1) * 12) / CGFloat(columns) - 50)
        let representedRecordingIDs = Set(grouped.finished.filter { completed($0) }
            .flatMap { linkedRecordingIDs(for: $0) })
        let remainingRecorded = day.recorded.filter { !representedRecordingIDs.contains($0.id) }

        return VStack(alignment: .leading, spacing: 12) {
            if !grouped.pending.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0),
                    spacing: 12, alignment: .top), count: columns),
                    alignment: .leading, spacing: 12) {
                    ForEach(grouped.pending) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            ATHLTHStudioPlannedWorkoutHeroCard(
                                workout: entry.workout,
                                availableWidth: cardWidth,
                                isCompleted: false,
                                isSkipped: false,
                                canStart: canStart(entry, alreadyCompleted: false),
                                onOpen: { onOpenWorkout(entry) },
                                onStart: { onStartWorkout(entry) },
                                compact: columns == 2
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("athlth-ipad-planned-workout-\(entry.id)")
                            .contextMenu { workoutActions(entry) }
                            Menu {
                                workoutActions(entry)
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.headline)
                                    .foregroundStyle(ink)
                                    .frame(width: 42, height: 44)
                                    .background(cream, in: RoundedRectangle(cornerRadius: 13))
                            }
                            .accessibilityLabel(tr("Workout actions", "Valg for økten"))
                        }
                    }
                }
                .accessibilityIdentifier("athlth-ipad-pending-workout-grid")
            }

            if !grouped.finished.isEmpty || !remainingRecorded.isEmpty {
                if !grouped.pending.isEmpty { Divider() }
                Text(tr("Completed and recorded", "Fullførte og registrerte økter"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(grouped.finished) { entry in
                        let done = completed(entry)
                        let receipt = session.recordedTimes(for: entry.workout.id)
                        let ids = linkedRecordingIDs(for: entry)
                        let recording = day.recorded.first { ids.contains($0.id) }
                        let time = recording.map(ATHLTHStudioRecordedWorkouts.timeRange)
                            ?? receipt?.startedAt.formatted(date: .omitted, time: .shortened)
                            ?? entry.workout.scheduledStart?.formatted(date: .omitted, time: .shortened)
                        let duration: String? = {
                            if let recording {
                                return "\(Int(recording.duration / 60)) min"
                            }
                            if let receipt, let end = receipt.endedAt, end >= receipt.startedAt {
                                return "\(Int(end.timeIntervalSince(receipt.startedAt) / 60)) min"
                            }
                            return nil
                        }()
                        compactFinishedRow(
                            title: entry.workout.title, time: time, duration: duration,
                            status: done ? tr("Completed", "Fullført") : tr("Skipped", "Hoppet over"),
                            symbol: done ? "checkmark.circle.fill" : "minus.circle",
                            action: { onOpenWorkout(entry) }
                        )
                        .accessibilityIdentifier("athlth-ipad-planned-workout-\(entry.id)")
                        .contextMenu { workoutActions(entry) }
                        if entry.id != grouped.finished.last?.id || !remainingRecorded.isEmpty {
                            Divider().padding(.leading, 28)
                        }
                    }
                    ForEach(remainingRecorded) { workout in
                        compactFinishedRow(
                            title: recordedActivityTitle(workout),
                            time: ATHLTHStudioRecordedWorkouts.timeRange(workout),
                            duration: "\(Int(workout.duration / 60)) min",
                            status: tr("Recorded", "Registrert"),
                            symbol: "checkmark.circle.fill",
                            action: { onInspect(workout) }
                        )
                        if workout.id != remainingRecorded.last?.id {
                            Divider().padding(.leading, 28)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(cream.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("athlth-ipad-finished-workout-list")
            }
        }
        .accessibilityIdentifier("athlth-ipad-selected-day-workouts")
    }

    private func recordedActivityTitle(_ workout: WorkoutSummary) -> String {
        switch workout.activity {
        case .strength: return ATHLTHPlannedWorkoutType.strength.title
        case .running: return ATHLTHPlannedWorkoutType.running.title
        case .walking, .hiking: return ATHLTHPlannedWorkoutType.walking.title
        case .cycling: return ATHLTHPlannedWorkoutType.cycling.title
        case .yoga: return tr("Yoga", "Yoga")
        default: return workout.activity.rawValue.capitalized
        }
    }

    private func linkedRecordingIDs(for entry: ATHLTHStudioSchedule.Occurrence) -> Set<UUID> {
        var ids = Set<UUID>()
        if let planID = entry.planID,
           let id = session.linkedHealthWorkoutID(planID: planID, sessionID: entry.workout.id) {
            ids.insert(id)
        }
        for log in strength.workoutHistory where log.isFinished && log.plannedSessionID == entry.workout.id {
            ids.insert(log.id)
            if let id = log.healthMetrics.healthKitWorkoutUUID { ids.insert(id) }
        }
        return ids
    }

    private func compactFinishedRow(
        title: String, time: String?, duration: String?, status: String,
        symbol: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(bronze)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink)
                    Text([status, time, duration].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(bronze)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func weekSelectionSummary(
        _ day: ATHLTHStudioHomeWeek.Day?
    ) -> String {
        guard let day else {
            return tr("Select a day in the calendar", "Velg en dag i kalenderen")
        }
        if !day.planned.isEmpty {
            let plannedLabel = tr(
                ATHLTHStudioHomeWeek.plannedCountLabel(
                    day.planned.count, norwegian: false
                ),
                ATHLTHStudioHomeWeek.plannedCountLabel(
                    day.planned.count, norwegian: true
                )
            )
            guard !day.recorded.isEmpty else { return plannedLabel }
            let logged = day.recorded.count == 1
                ? tr("1 recorded workout", "1 registrert økt")
                : tr("\(day.recorded.count) recorded workouts",
                     "\(day.recorded.count) registrerte økter")
            return plannedLabel + " · " + logged
        }
        if !day.restDays.isEmpty {
            return tr("Planned rest day", "Planlagt hviledag")
        }
        if !day.recorded.isEmpty {
            return day.recorded.count == 1
                ? tr("1 recorded workout", "1 registrert økt")
                : tr("\(day.recorded.count) recorded workouts",
                     "\(day.recorded.count) registrerte økter")
        }
        return tr("No workout scheduled", "Ingen økt planlagt")
    }

    private func dayTile(
        _ day: ATHLTHStudioHomeWeek.Day,
        selected: Bool
    ) -> some View {
        let planned = day.planned.first
        let firstRecorded = day.recorded.first
        let isToday = Calendar.current.isDateInToday(day.date)
        let isRest = planned == nil && !day.restDays.isEmpty
        // All planned sessions must complete before the day gets a check.
        let isPlanCompleted = ATHLTHStudioDayCompletionPolicy
            .allPlannedCompleted(day.planned, isCompleted: completed)
        let plannedMinutes = day.planned.reduce(0) {
            $0 + max(0, $1.workout.durationMinutes ?? 0)
        }
        let pluralWorkoutLabel = tr(
            "\(day.planned.count) workouts",
            "\(day.planned.count) økter"
        )
        let shortLabel: String =
            day.planned.count > 1 ? pluralWorkoutLabel :
            planned?.workout.title ??
            (isRest ? tr("Rest day", "Hviledag") :
             firstRecorded?.activity.rawValue.capitalized ??
             tr("No workout", "Ingen økt"))
        let iconName: String =
            (isPlanCompleted || (planned == nil && firstRecorded != nil))
                ? "checkmark.circle.fill"
                : planned?.workout.kind.systemImage ??
                  (isRest ? "moon.zzz" : "minus")

        return Button {
            followsToday = false
            selectedDate = day.date
            // Keep the selected day's workouts directly below the week strip.
            // The side inspector is reserved for conversations and activity.
        } label: {
            VStack(spacing: 8) {
                HStack {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption)
                    Spacer(minLength: 3)
                    if isToday {
                        Circle().fill(selected ? Color.white : bronze)
                            .frame(width: 5, height: 5)
                    }
                }
                Text(day.date.formatted(.dateTime.day()))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: iconName)
                    .font(.system(size: 21))
                    .frame(height: 26)
                Text(shortLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32, alignment: .top)
                if planned != nil && !day.recorded.isEmpty {
                    Label(
                        "\(day.recorded.count) " + tr("recorded", "registrert"),
                        systemImage: "checkmark.circle"
                    )
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(0.85)
                } else if day.planned.count > 1 {
                    Text("\(plannedMinutes) min")
                        .font(.caption2)
                        .opacity(0.8)
                } else if let item = planned,
                          let minutes = item.workout.durationMinutes {
                    Text("\(minutes) min")
                        .font(.caption)
                        .opacity(0.8)
                } else if let recorded = firstRecorded {
                    Text("\(Int(recorded.duration / 60)) min")
                        .font(.caption)
                        .opacity(0.8)
                } else {
                    Text(" ").font(.caption)
                }
            }
            .foregroundStyle(selected ? Color.white : ink)
            .padding(11)
            .frame(maxWidth: .infinity,
                   minHeight: dynamicTypeSize.isAccessibilitySize ? 178 : 153,
                   alignment: .topLeading)
            .background(
                selected ? ink : cream,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            day.date.formatted(date: .complete, time: .omitted) + ", " +
            shortLabel
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(tr(
            "Show this day's workouts beneath the calendar",
            "Vis dagens økter under kalenderen"
        ))
        .accessibilityIdentifier(
            "athlth-ipad-week-day-\(Calendar.current.startOfDay(for: day.date).timeIntervalSince1970)"
        )
    }

    private func shiftWeek(_ offset: Int) {
        followsToday = false
        selectedDate = ATHLTHStudioHomeWeek.shiftedWeek(
            from: selectedDate, offset: offset
        )
    }

    private func skipped(_ item: ATHLTHStudioSchedule.Occurrence) -> Bool {
        item.planID.map { session.isPlanSessionSkipped(planID: $0, sessionID: item.workout.id) } ?? false
    }

    private func completed(_ item: ATHLTHStudioSchedule.Occurrence) -> Bool {
        guard !item.workout.isExplicitRestDay, !skipped(item) else { return false }
        if session.recordedTimes(for: item.workout.id)?.endedAt != nil { return true }
        guard let planID = item.planID else {
            return strength.workoutHistory.contains {
                $0.isFinished && $0.plannedSessionID == item.workout.id
            }
        }
        let key = "\(planID.uuidString):\(item.workout.id.uuidString)"
        if let projection = homeProjection,
           projection.accountID == session.profile.userID,
           let cached = projection.completedByPlanSession[key] {
            return cached
        }
        return session.isPlanSessionCompleted(
            planID: planID, sessionID: item.workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
    }

    private func canStart(
        _ item: ATHLTHStudioSchedule.Occurrence,
        alreadyCompleted: Bool? = nil
    ) -> Bool {
        guard let planID = item.planID,
              !item.workout.isExplicitRestDay,
              !session.isPlanSessionSkipped(planID: planID, sessionID: item.workout.id),
              !(alreadyCompleted ?? completed(item)) else { return false }
        return true
    }

    private func openOrStart(_ item: ATHLTHStudioSchedule.Occurrence) {
        if canStart(item) { onStartWorkout(item) }
        else { onOpenWorkout(item) }
    }

    @ViewBuilder
    private func workoutActions(_ item: ATHLTHStudioSchedule.Occurrence) -> some View {
        if canStart(item) {
            Button {
                onStartWorkout(item)
            } label: {
                Label(tr("Start workout", "Start økt"), systemImage: "play.fill")
            }
            if [.running, .walking, .strength].contains(item.workout.kind) {
                Button {
                    onSendToWatch(item)
                } label: {
                    Label(tr("Send to Apple Watch", "Send til Apple Watch"),
                          systemImage: "applewatch")
                }
            }
            Menu {
                Button(tr("In 5 minutes", "Om 5 minutter")) {
                    onStartAfter(item, 300)
                }
                Button(tr("In 15 minutes", "Om 15 minutter")) {
                    onStartAfter(item, 900)
                }
                Button(tr("In 30 minutes", "Om 30 minutter")) {
                    onStartAfter(item, 1800)
                }
            } label: {
                Label(tr("Start later", "Start senere"), systemImage: "clock")
            }
        }
        Button {
            onOpenWorkout(item)
        } label: {
            Label(tr("Workout details", "Øktdetaljer"), systemImage: "info.circle")
        }
    }

    /// Keep progress on a single calm surface. On wide iPads the chart and
    /// the selected week's totals share a row; on narrow windows they stack.
    private func progressCard(
        wide: Bool,
        data: ATHLTHStudioAnalytics.Snapshot,
        week: ATHLTHStudioHomeWeek.Snapshot
    ) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("Progress", "Fremgang"))
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                Spacer(minLength: 4)
                Menu {
                    Button(tr("7 days", "7 dager")) { periodDays = 7 }
                    Button(tr("28 days", "28 dager")) { periodDays = 28 }
                    Button(tr("90 days", "90 dager")) { periodDays = 90 }
                } label: {
                    Label("\(periodDays) " + tr("days", "dager"),
                          systemImage: "chevron.down")
                        .font(.caption)
                }
                .tint(ink)
            }

            if health.isRefreshing && health.lastSuccessfulRefreshAt == nil &&
                strength.workoutHistory.isEmpty {
                ProgressView(tr("Loading workouts", "Henter økter"))
                    .frame(maxWidth: .infinity, minHeight: 92)
            } else {
                if wide {
                    HStack(alignment: .center, spacing: 22) {
                        historyChart(data)
                            .frame(maxWidth: .infinity)
                        Rectangle()
                            .fill(outline.opacity(0.85))
                            .frame(width: 1)
                        weeklyActivitySummary(week)
                            .frame(width: 205, alignment: .leading)
                    }
                } else {
                    historyChart(data)
                    Rectangle()
                        .fill(outline.opacity(0.75))
                        .frame(height: 1)
                    weeklyActivitySummary(week)
                }
            }

            Button(action: onOpenInsights) {
                Label(tr("View progress", "Se fremgang"),
                      systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(bronze)
            .frame(minHeight: 44, alignment: .leading)
        }
        .padding(19)
        .frame(maxWidth: .infinity, minHeight: 225, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline.opacity(0.45), lineWidth: 0.6))
        .accessibilityIdentifier("athlth-ipad-progress")
    }

    @ViewBuilder
    private func historyChart(
        _ data: ATHLTHStudioAnalytics.Snapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("Recorded training time", "Registrert treningstid"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if data.sessions > 0 {
                Text("\(data.sessions) " + tr("sessions", "økter") + "  ·  " +
                     String(format: "%.1f t", data.minutes / 60))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Chart(data.days) { day in
                    AreaMark(
                        x: .value("Date", day.date),
                        y: .value("Hours", day.minutes / 60)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [bronze.opacity(0.15), bronze.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Hours", day.minutes / 60)
                    )
                    .foregroundStyle(bronze)
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 110)
                .chartLegend(.hidden)
                .accessibilityLabel(tr(
                    "Daily recorded training hours",
                    "Registrerte treningstimer per dag"
                ))
            } else {
                Label(
                    tr("No recorded workouts for this period",
                       "Ingen registrerte økter i denne perioden"),
                    systemImage: "chart.xyaxis.line"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100,
                       alignment: .leading)
            }
        }
    }

    private func weeklyActivitySummary(
        _ week: ATHLTHStudioHomeWeek.Snapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("SELECTED WEEK", "VALGT UKE"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(bronze)
            HStack(alignment: .firstTextBaseline) {
                Text("\(week.plannedCount)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                Text(tr("planned workouts", "planlagte økter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(week.recordedCount)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                Text(tr("recorded workouts", "registrerte økter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(tr(
                "Recorded workouts do not automatically mark a plan complete.",
                "Registrerte økter markerer ikke automatisk en plan som fullført."
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("athlth-ipad-week-totals")
    }

    /// Shared HealthKit recovery data; compact premium iPad presentation
    /// mirrors the iPhone Insights hierarchy without inventing a score.
    private var compactReadinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("ATHLTH INSIGHT", "ATHLTH INNSIKT"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(bronze)
                    Text(tr("Today's readiness", "Dagens form"))
                        .font(.system(size: 23, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 4)
                Button(action: onOpenInsights) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(bronze)
                        .frame(width: 34, height: 34)
                        .background(cream, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Open Insights", "Åpne Innsikt"))
            }

            if health.isRefreshing && health.lastSuccessfulRefreshAt == nil {
                HStack(spacing: 12) {
                    ProgressView().tint(bronze)
                    Text(tr("Updating signals", "Oppdaterer treningssignaler"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            } else if hasHealth, let score = health.recovery.score {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(bronze.opacity(0.13), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                            .stroke(
                                bronze,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text("\(score)")
                                .font(.system(size: 33, weight: .semibold,
                                              design: .rounded))
                                .foregroundStyle(ink)
                                .monospacedDigit()
                            Text("/ 100")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tr(
                        "Readiness score", "Dagsform"
                    ))
                    .accessibilityValue("\(score) av 100")

                    VStack(alignment: .leading, spacing: 7) {
                        Text(readinessTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(tr(
                            "Your recovery, sleep and cardiovascular signals.",
                            "Restitusjon, søvn og kroppens signaler."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if hasHealth, let diagnostics = health.recovery.diagnostics {
                VStack(alignment: .leading, spacing: 7) {
                    Label(tr("Building your baseline", "Kartlegger dagsformen"),
                          systemImage: "chart.xyaxis.line")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text("\(diagnostics.completeDays)/\(diagnostics.requiredDays) " +
                         tr("complete days", "dager med fullstendige data"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 98,
                       alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundStyle(bronze)
                    Text(tr("Connect health data", "Koble til helsedata"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Your readiness appears here when enough data is available.",
                        "Dagsformen vises her når det finnes tilstrekkelig med data."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 98,
                       alignment: .leading)
            }

            Rectangle()
                .fill(outline.opacity(0.60))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 7) {
                readinessSignal(
                    title: tr("Sleep", "Søvn"),
                    value: hasHealth && health.sleep.totalAsleep > 0
                        ? String(format: "%.1f t",
                                 health.sleep.totalAsleep / 3_600)
                        : "—"
                )
                readinessSignal(
                    title: "HRV",
                    value: hasHealth ? health.heart.hrvMilliseconds.map {
                        String(format: "%.0f ms", $0)
                    } ?? "—" : "—"
                )
                readinessSignal(
                    title: tr("Resting HR", "Hvilepuls"),
                    value: hasHealth ? health.heart.restingHeartRate.map {
                        String(format: "%.0f bpm", $0)
                    } ?? "—" : "—"
                )
            }

            Button {
                if hasHealth {
                    showingReadinessExplanation = true
                } else {
                    onOpenSettings()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(tr("Understand today's form", "Forstå dagens form"))
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(bronze)
                .frame(minHeight: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(
                    colors: [.white, cream],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(bronze.opacity(0.17), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("athlth-ipad-readiness-compact")
    }

    private func readinessSignal(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.80)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.86),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private var readinessTitle: String {
        switch health.recovery.state {
        case .ready:
            tr("Strong recovery", "God restitusjon")
        case .balanced:
            tr("Balanced signals", "Balanserte signaler")
        case .takeItEasy:
            tr("Consider taking it easy", "Vurder å ta det roligere")
        case .recover:
            tr("Focus on recovery", "Prioriter restitusjon")
        case .buildingBaseline:
            tr("Building baseline", "Bygger normal")
        }
    }

    private func weekLabel(_ plan: TrainingPlan) -> String {
        guard let start = plan.startDate, !plan.weeks.isEmpty else {
            return tr("Plan dates not set", "Planen mangler datoer")
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: .now)
        ).day ?? 0
        let weekIndex = max(0, min(plan.weeks.count - 1, days / 7))
        return tr("Week \(weekIndex + 1) of \(plan.weeks.count)",
                  "Uke \(weekIndex + 1) av \(plan.weeks.count)")
    }
}
