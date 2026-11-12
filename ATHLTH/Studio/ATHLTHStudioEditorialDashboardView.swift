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
    static func allPlannedCompleted<Item>(
        _ items: [Item],
        isCompleted: (Item) -> Bool
    ) -> Bool {
        !items.isEmpty && items.allSatisfy(isCompleted)
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

/// Remote Ghost updates own their SwiftUI state, so a four-second spectator
/// refresh never invalidates the entire Studio Home calendar and charts.
private struct ATHLTHStudioGhostHomeStatusView: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: ATHLTHPrivateGhostSpectatorSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot, snapshot.isFresh() {
                ATHLTHStudioPrivateGhostSpectatorCard(snapshot: snapshot)
            }
        }
        .task(id: "\(session.profile.userID.uuidString)-\(session.signedIn)-\(scenePhase == .active)") {
            snapshot = nil
            guard ATHLTHDeviceRole.isIPad, session.signedIn,
                  scenePhase == .active else { return }
            while !Task.isCancelled {
                let userID = session.profile.userID
                let fetched = await ATHLTHPrivateGhostSpectatorStore.fetch(
                    for: userID
                )
                guard !Task.isCancelled, userID == session.profile.userID
                else { return }
                snapshot = fetched
                try? await Task.sleep(
                    for: .seconds(snapshot == nil ? 12 : 4)
                )
            }
        }
    }
}

/// A local strength session takes priority over the remote read-only card.
/// Neither remote fetch nor refresh changes Home's other derived data.
private struct ATHLTHStudioStrengthHomeStatusView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: ATHLTHPrivateLiveStrengthSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            if strength.activeWorkout != nil {
                ATHLTHStudioLiveStrengthReadOnlyCard()
            } else if let snapshot, snapshot.isFresh() {
                ATHLTHStudioRemoteStrengthStatusCard(snapshot: snapshot)
            }
        }
        .task(id: "\(session.profile.userID.uuidString)-\(session.signedIn)-\(scenePhase == .active)") {
            snapshot = nil
            guard ATHLTHDeviceRole.isIPad, session.signedIn,
                  scenePhase == .active else { return }
            while !Task.isCancelled {
                let account = session.profile.userID
                let fetched = await ATHLTHPrivateLiveStrengthStatusStore.fetch(
                    for: account
                )
                guard !Task.isCancelled, account == session.profile.userID
                else { return }
                snapshot = fetched
                try? await Task.sleep(for: .seconds(12))
            }
        }
    }
}

/// iPad-only Studio home, inspired by the approved airy ATHLTH Studio reference.
/// The content is sourced from existing local session and Health stores; no
/// demonstration values, artificial readiness scores or implicit completions.
struct ATHLTHStudioEditorialDashboardView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    let onInspect: (WorkoutSummary) -> Void
    /// The current week strip remains on Home; details dock on the right.
    let onSelectWeekDay: (Date) -> Void
    let onOpenPlanner: () -> Void
    let onOpenInsights: () -> Void
    let onOpenHistory: () -> Void
    let onOpenSettings: () -> Void
    let onOpenLibrary: () -> Void
    let onOpenWorkout: (ATHLTHStudioSchedule.Occurrence) -> Void
    let onStartQuick: () -> Void
    let onStartWorkout: (ATHLTHStudioSchedule.Occurrence) -> Void
    let onSendToWatch: (ATHLTHStudioSchedule.Occurrence) -> Void
    let onStartAfter: (ATHLTHStudioSchedule.Occurrence, TimeInterval) -> Void
    @Binding var focusedPlanningDate: Date?

    @Binding var selectedDate: Date
    @State private var periodDays = 28
    /// Auto-follow today unless the user explicitly browses a date.
    @State private var followsToday = true
    @State private var showingReadinessExplanation = false

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
        if let active = session.activePlan,
           !session.pausedTrainingPlanIDs.contains(active.id),
           !session.deactivatedTrainingPlanIDs.contains(active.id) {
            return active
        }
        return session.nextTrainingPlan
    }

    private func nextWorkout(
        from upcoming: [ATHLTHStudioSchedule.Occurrence]
    ) -> ATHLTHStudioSchedule.Occurrence? {
        upcoming.first { item in
            guard ATHLTHStudioSchedule.isUpcoming(item) else { return false }
            guard let planID = item.planID else { return true }
            return !session.isPlanSessionSkipped(planID: planID, sessionID: item.workout.id)
                && !completed(item)
                && !item.workout.isExplicitRestDay
        }
    }

    /// A transparent activity hint, not a recovery diagnosis or AI promise.
    /// Calculated once from the same training history and next session
    /// used by the rest of the current Home render.
    private func homeRecommendation(
        recorded: [WorkoutSummary],
        next: ATHLTHStudioSchedule.Occurrence?
    ) -> ATHLTHStudioHomeRecommendation.Result {
        ATHLTHStudioHomeRecommendation.make(
            nextWorkoutTitle: next?.workout.title,
            workouts: recorded
        )
    }

    private func calendarWeek(
        recorded: [WorkoutSummary],
        planned: [ATHLTHStudioSchedule.Occurrence]
    ) -> ATHLTHStudioHomeWeek.Snapshot {
        ATHLTHStudioHomeWeek.make(
            plans: session.trainingPlans,
            standalone: session.standalonePlannedSessions,
            recorded: recorded,
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            now: selectedDate,
            plannedOverride: planned
        )
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
                let workouts = recordedWorkouts
                let windows = ATHLTHStudioSchedule.studioHomeWindows(
                    plans: session.trainingPlans,
                    standalone: session.standalonePlannedSessions,
                    pausedPlanIDs: session.pausedTrainingPlanIDs,
                    deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
                    selectedWeekDate: selectedDate
                )
                let week = calendarWeek(recorded: workouts, planned: windows.week)
                let width = geometry.size.width
                let split = width >= 730 && !dynamicTypeSize.isAccessibilitySize

                ScrollView {
                    VStack(alignment: .leading, spacing: split ? 20 : 16) {
                        // Home is one cohesive workspace. The current form
                        // belongs at the top right, never below the week or
                        // alongside the selected-day schedule.
                        if split {
                            HStack(alignment: .top, spacing: 18) {
                                titleRow(expanded: true)
                                    .frame(maxWidth: .infinity)
                                compactReadinessCard
                                    .frame(width: min(390, max(310, width * 0.30)))
                            }
                        } else {
                            titleRow(expanded: false)
                            compactReadinessCard
                        }

                        activePlanSummary
                        // The selected day's full schedule is INSIDE the
                        // weekly card, immediately below its summary.
                        weekCard(week, width: width)

                        ATHLTHStudioGhostHomeStatusView().id(session.profile.userID)
                        ATHLTHStudioStrengthHomeStatusView().id(session.profile.userID)
                        ATHLTHStudioHomeCommunitySummary()
                        progressCard(wide: split, recorded: workouts, week: week)
                    }
                    .padding(.horizontal, split ? 22 : 14)
                    .padding(.vertical, 17)
                    .frame(maxWidth: 1500)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(cream.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, followsToday, focusedPlanningDate == nil {
                selectedDate = .now
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSCalendarDayChanged
        )) { _ in
            if followsToday, focusedPlanningDate == nil {
                selectedDate = .now
            }
        }
        .sheet(isPresented: $showingReadinessExplanation) {
            ATHLTHReadinessExplanationSheet(
                recovery: health.recovery,
                sleep: health.sleep,
                heart: health.heart
            )
        }
    }

    private func titleRow(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ATHLTH")
                .font(.caption.weight(.semibold))
                .tracking(2.4)
                .foregroundStyle(bronze)
            Text(tr("Your training today", "Treningen din i dag"))
                .font(.system(size: expanded ? 32 : 27, weight: .regular, design: .serif))
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button {
                    focusedPlanningDate = Calendar.current.startOfDay(for: .now)
                } label: {
                    Label(tr("Plan workout", "Planlegg økt"), systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink)
                .frame(minHeight: 44)
                Button(action: onStartQuick) {
                    Label(tr("Start workout", "Start økt"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(bronze)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { bounds in
                Image("HomeHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: bounds.size.width, height: bounds.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [cream, cream.opacity(0.95), cream.opacity(0.45)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
            }
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityIdentifier("athlth-ipad-training-command-header")
    }

    private var activePlanSummary: some View {
        Button(action: onOpenPlanner) {
            HStack(spacing: 18) {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(bronze)
                    .frame(width: 48, height: 48)
                    .background(cream, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(program?.id == session.activePlan?.id && program != nil
                         ? tr("ACTIVE TRAINING PLAN", "AKTIV TRENINGSPLAN")
                         : tr("TRAINING PLAN", "TRENINGSPLAN"))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(program?.title ?? tr("Create your training plan", "Lag treningsplanen din"))
                        .font(.system(.title3, design: .serif, weight: .medium))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.leading)
                    if let plan = program {
                        Text(weekLabel(plan)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(bronze)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr("Open your training plan", "Åpne treningsplanen din"))
    }

    private var planCard: some View {
        Button(action: onOpenPlanner) {
            VStack(alignment: .leading, spacing: 16) {
                Label(tr("ACTIVE TRAINING PLAN", "AKTIV TRENINGsPLAN").uppercased(),
                      systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(bronze)

                if let plan = program {
                    Text(plan.title)
                        .font(.system(size: 27, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                    Text(weekLabel(plan))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    let progress = session.trainingPlanProgress(
                        plan,
                        healthWorkouts: health.workouts,
                        strengthHistory: strength.workoutHistory
                    )
                    let fraction = progress.totalSessions > 0
                        ? min(1, max(0, Double(progress.completedSessions) /
                                          Double(progress.totalSessions)))
                        : 0.0

                    HStack(spacing: 12) {
                        ProgressView(value: fraction)
                            .tint(bronze)
                        Text("\(Int((fraction * 100).rounded())) %")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(ink)
                    }
                    Text("\(progress.completedSessions) / \(progress.totalSessions) " +
                         tr("workouts completed", "økter fullført"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(tr("Build your training plan", "Bygg treningsplanen din"))
                        .font(.system(size: 25, weight: .medium, design: .serif))
                        .foregroundStyle(ink)
                    Text(tr("Create a plan in Plan Studio to follow it here.",
                            "Opprett en plan i Plan Studio for å følge den her."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                Label(
                    program == nil ? tr("Create plan", "Opprett plan")
                        : tr("View full plan", "Se hele planen"),
                    systemImage: "arrow.up.right"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(bronze)
            }
            .frame(maxWidth: .infinity, minHeight: 204, alignment: .leading)
            .padding(21)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white)
                    .overlay(alignment: .trailing) {
                        Image("HomeHero")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 255)
                            .opacity(0.15)
                            .mask(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.5), .white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("athlth-ipad-active-training-plan")
    }

    private func recommendationCard(
        _ recommendation: ATHLTHStudioHomeRecommendation.Result,
        next: ATHLTHStudioSchedule.Occurrence?
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(bronze)
                .frame(width: 44, height: 44)
                .background(cream, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("Today's recommendation", "Dagens anbefaling"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bronze)
                Text(tr(recommendation.titleEnglish, recommendation.titleNorwegian))
                    .font(.system(size: 19, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                Text(tr(recommendation.reasonEnglish, recommendation.reasonNorwegian))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button {
                if let item = next {
                    onOpenWorkout(item)
                } else {
                    onStartQuick()
                }
            } label: {
                Label(
                    next == nil
                        ? tr("Choose workout", "Velg økt")
                        : tr("View workout", "Se økt"),
                    systemImage: "arrow.up.right"
                )
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .tint(bronze)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline.opacity(0.45), lineWidth: 0.6))
        .accessibilityIdentifier("athlth-ipad-home-recommendation")
    }

    private func nextWorkoutCard(
        _ next: ATHLTHStudioSchedule.Occurrence?
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Next workout", "Neste økt"))
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(ink)
            if let item = next {
                Label(item.workout.title, systemImage: item.workout.kind.systemImage)
                    .font(.headline)
                    .foregroundStyle(ink)
                    .lineLimit(2)
                Text(item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let distance = item.workout.targetDistanceKilometers, distance > 0 {
                        Text(distance.formatted(.number.precision(.fractionLength(1))) + " km")
                    }
                    if let minutes = item.workout.durationMinutes {
                        Text("· \(minutes) min")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    openOrStart(item)
                } label: {
                    Label(
                        canStart(item) ? tr("Start workout", "Start økt")
                            : tr("Open workout", "Åpne økt"),
                        systemImage: canStart(item) ? "play.fill" : "arrow.up.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ink)
                .controlSize(.large)
                .contextMenu { workoutActions(item) }
            } else {
                Text(tr("Your next planned workout will appear here.",
                        "Neste planlagte økt vises her."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    focusedPlanningDate = Calendar.current.startOfDay(for: .now)
                } label: {
                    Label(tr("Plan workout", "Planlegg økt"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 246, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline.opacity(0.45), lineWidth: 0.6))
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
                selectedDayWorkouts(activeDay)
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

    /// Full planned workout details sit immediately below the selected-day
    /// count. Reuses the same occurrence and workout detail actions as Plan.
    private func selectedDayWorkouts(_ day: ATHLTHStudioHomeWeek.Day) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(day.planned) { entry in
                let isCompleted = completed(entry)
                let isSkipped = entry.planID.map {
                    session.isPlanSessionSkipped(
                        planID: $0, sessionID: entry.workout.id
                    )
                } ?? false

                HStack(spacing: 8) {
                    Button {
                        onOpenWorkout(entry)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                if let scheduled = entry.workout.scheduledStart {
                                    Text(scheduled.formatted(
                                        date: .omitted, time: .shortened
                                    ))
                                    .font(.system(size: 17, weight: .bold,
                                                  design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(ink)
                                } else {
                                    Text(tr("No time", "Uten tid"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(tr("Start time", "Klokkeslett"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 84, alignment: .leading)

                            Rectangle()
                                .fill(outline.opacity(0.8))
                                .frame(width: 1, height: 40)

                            Image(systemName: entry.workout.kind.systemImage)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(bronze)
                                .frame(width: 35, height: 35)
                                .background(.white.opacity(0.7),
                                            in: RoundedRectangle(cornerRadius: 11))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.workout.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ink)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 8) {
                                    if let minutes = entry.workout.durationMinutes {
                                        Label("\(minutes) min", systemImage: "clock")
                                    }
                                    if isCompleted {
                                        Label(tr("Completed", "Fullført"),
                                              systemImage: "checkmark.circle.fill")
                                    } else if isSkipped {
                                        Text(tr("Skipped", "Hoppet over"))
                                    } else {
                                        Text(tr("Planned", "Planlagt"))
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(bronze)
                        }
                        .padding(.horizontal, 13)
                        .frame(minHeight: 74)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cream, in: RoundedRectangle(cornerRadius: 15))
                        .contentShape(RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        (entry.workout.scheduledStart?.formatted(
                            date: .omitted, time: .shortened
                        ) ?? tr("No set time", "Uten klokkeslett"))
                        + ", " + entry.workout.title
                    )
                    .accessibilityHint(tr(
                        "Open full workout details",
                        "Åpne alle detaljer for treningsøkten"
                    ))
                    .accessibilityIdentifier(
                        "athlth-ipad-planned-workout-\(entry.id)"
                    )
                    .contextMenu { workoutActions(entry) }

                    Menu {
                        workoutActions(entry)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(ink)
                            .frame(width: 42, height: 44)
                            .background(cream,
                                        in: RoundedRectangle(cornerRadius: 13))
                    }
                    .accessibilityLabel(tr("Workout actions", "Valg for økten"))
                }
            }

            ForEach(day.recorded) { workout in
                Button {
                    onInspect(workout)
                } label: {
                    HStack(spacing: 12) {
                        Text(workout.startDate.formatted(
                            date: .omitted, time: .shortened
                        ))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 84, alignment: .leading)

                        Rectangle()
                            .fill(outline.opacity(0.8))
                            .frame(width: 1, height: 30)

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(bronze)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.activity.rawValue.capitalized)
                                .font(.subheadline.weight(.semibold))
                            Text("\(Int(workout.duration / 60)) min · " +
                                 tr("Recorded workout", "Registrert økt"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(bronze)
                    }
                    .foregroundStyle(ink)
                    .padding(13)
                    .background(cream, in: RoundedRectangle(cornerRadius: 15))
                    .contentShape(RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("athlth-ipad-selected-day-workouts")
    }

    private func weekSelectionSummary(
        _ day: ATHLTHStudioHomeWeek.Day?
    ) -> String {
        guard let day else {
            return tr("Select a day in the calendar", "Velg en dag i kalenderen")
        }
        if !day.planned.isEmpty {
            let plannedLabel = ATHLTHStudioHomeWeek.plannedCountLabel(
                day.planned.count,
                norwegian: ATHLTHLocalization.choose(
                    english: false, norwegian: true
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

    private func completed(_ item: ATHLTHStudioSchedule.Occurrence) -> Bool {
        guard let planID = item.planID else { return false }
        return session.isPlanSessionCompleted(
            planID: planID,
            sessionID: item.workout.id,
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
        recorded: [WorkoutSummary],
        week: ATHLTHStudioHomeWeek.Snapshot
    ) -> some View {
        let data = ATHLTHStudioAnalytics.snapshot(
            from: recorded,
            days: periodDays
        )
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

    private var compactReadinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Today's readiness", "Dagens form"))
                    .font(.system(size: 21, weight: .medium, design: .serif))
                    .foregroundStyle(ink)
                Spacer(minLength: 6)
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(bronze)
                    .font(.subheadline)
            }
            if health.isRefreshing && health.lastSuccessfulRefreshAt == nil {
                ProgressView(tr("Updating", "Oppdaterer"))
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if hasHealth, let score = health.recovery.score {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(score)")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                    Text(readinessTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if hasHealth, let diagnostics = health.recovery.diagnostics {
                Text(tr("Building your baseline", "Kartlegger dagsform"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                Text("\(diagnostics.completeDays)/\(diagnostics.requiredDays) " +
                     tr("complete days", "komplette dager"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(tr(
                    "Apple Health data unavailable",
                    "Helsedata er ikke tilgjengelige"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider().overlay(outline)
            Text(tr("TRAINING SIGNALS", "TRENINGSSIGNALER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(bronze)

            VStack(alignment: .leading, spacing: 7) {
                compactMetric(
                    title: tr("Sleep", "Søvn"),
                    value: hasHealth && health.sleep.totalAsleep > 0
                        ? String(format: "%.1f t", health.sleep.totalAsleep / 3_600)
                        : "—"
                )
                compactMetric(
                    title: "HRV",
                    value: hasHealth ? health.heart.hrvMilliseconds.map {
                        String(format: "%.0f ms", $0)
                    } ?? "—" : "—"
                )
                compactMetric(
                    title: tr("Resting HR", "Hvilepuls"),
                    value: hasHealth ? health.heart.restingHeartRate.map {
                        String(format: "%.0f bpm", $0)
                    } ?? "—" : "—"
                )
            }
            Spacer(minLength: 0)
            Button {
                if hasHealth {
                    showingReadinessExplanation = true
                } else {
                    onOpenSettings()
                }
            } label: {
                Label(tr("Details", "Detaljer"),
                      systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(bronze)
            .frame(minHeight: 40)
        }
        .padding(19)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline.opacity(0.45), lineWidth: 0.6))
        .accessibilityIdentifier("athlth-ipad-readiness-compact")
    }

    private func compactMetric(title: String, value: String) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
