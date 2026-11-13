import SwiftUI
import Charts

/// iPad Home V2: the first screen is a training cockpit, not a report.
/// Every action navigates to an existing ATHLTH destination. No HealthKit
/// access, AI suggestion, plan completion or server write is inferred here.
struct ATHLTHStudioDashboardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let onInspect: (WorkoutSummary) -> Void
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
    /// Stored at the Studio scene root so sidebar changes or window
    /// resizing cannot throw away an active day-planning session.
    @Binding var focusedPlanningDate: Date?

    @State private var periodDays = 28
    @State private var selectedWeekDate = Date.now
    @State private var showingReadinessExplanation = false

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var healthHasDataAccess: Bool {
        health.healthDataAvailable && health.hasRequestedAuthorization
    }

    private var snapshot: ATHLTHStudioAnalytics.Snapshot {
        ATHLTHStudioAnalytics.snapshot(from: health.workouts, days: periodDays)
    }

    private var upcoming: [ATHLTHStudioSchedule.Occurrence] {
        ATHLTHStudioSchedule.upcoming(
            plans: session.trainingPlans,
            standalone: session.standalonePlannedSessions,
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            now: .now,
            days: 14
        )
    }

    private var nextWorkout: ATHLTHStudioSchedule.Occurrence? {
        upcoming.first { entry in
            guard let planID = entry.planID else { return true }
            return !session.isPlanSessionSkipped(
                planID: planID, sessionID: entry.workout.id
            ) && !session.isPlanSessionCompleted(
                planID: planID,
                sessionID: entry.workout.id,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        }
    }

    private var week: ATHLTHStudioHomeWeek.Snapshot {
        ATHLTHStudioHomeWeek.make(
            plans: session.trainingPlans,
            standalone: session.standalonePlannedSessions,
            recorded: healthHasDataAccess ? health.workouts : [],
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            now: selectedWeekDate
        )
    }

    /// Header values always refer to the actual current week, even when the
    /// calendar below is browsing an earlier or later week.
    private var actualWeek: ATHLTHStudioHomeWeek.Snapshot {
        ATHLTHStudioHomeWeek.make(
            plans: session.trainingPlans,
            standalone: session.standalonePlannedSessions,
            recorded: healthHasDataAccess ? health.workouts : [],
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            now: .now
        )
    }

    private var headerPulse: ATHLTHStudioDashboardHeaderPulse {
        let current = actualWeek
        let confirmed = Set(current.days.flatMap(\.planned).compactMap {
            entry -> String? in
            guard let planID = entry.planID,
                  session.isPlanSessionCompleted(
                    planID: planID,
                    sessionID: entry.workout.id,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                  ) else { return nil }
            return entry.id
        })
        return ATHLTHStudioDashboardHeaderPulse.make(
            week: current,
            completedOccurrenceIDs: confirmed,
            healthAvailable: healthHasDataAccess
        )
    }

    private var headerProgram: TrainingPlan? {
        if let currentProgram { return currentProgram }
        return session.trainingPlans
            .filter {
                !session.pausedTrainingPlanIDs.contains($0.id) &&
                !session.deactivatedTrainingPlanIDs.contains($0.id) &&
                session.trainingPlanStatus($0) == .completed
            }
            .max {
                ($0.startDate ?? .distantPast) <
                ($1.startDate ?? .distantPast)
            }
    }

    private var recent: [WorkoutSummary] {
        Array(health.workouts.sorted { $0.startDate > $1.startDate }.prefix(2))
    }

    private var currentProgram: TrainingPlan? {
        if let active = session.activePlan,
           !session.pausedTrainingPlanIDs.contains(active.id),
           !session.deactivatedTrainingPlanIDs.contains(active.id) {
            return active
        }
        return session.nextTrainingPlan
    }

    var body: some View {
        GeometryReader { geometry in
            if let focusedPlanningDate {
                ATHLTHStudioFocusedWeekPlannerView(
                    initialDate: focusedPlanningDate,
                    onClose: { self.focusedPlanningDate = nil }
                )
            } else {
            let wide = geometry.size.width >= 795 &&
                !dynamicTypeSize.isAccessibilitySize
            let currentWeek = week
            let next = nextWorkout

            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    heading(wide: wide)

                    if wide {
                        HStack(alignment: .top, spacing: 15) {
                            todayCard(next)
                                .frame(maxWidth: .infinity)
                            readinessCard
                                .frame(width: max(285, min(370, geometry.size.width * 0.34)))
                        }
                    } else {
                        VStack(spacing: 14) {
                            todayCard(next)
                            readinessCard
                        }
                    }

                    weekCard(currentWeek, width: geometry.size.width)
                    ATHLTHiPadLiveWorkoutStatusCard()

                    if wide {
                        HStack(alignment: .top, spacing: 15) {
                            trainingDevelopment
                                .frame(maxWidth: .infinity)
                            activeProgram
                                .frame(width: max(285, min(370, geometry.size.width * 0.34)))
                        }
                    } else {
                        VStack(spacing: 14) {
                            trainingDevelopment
                            activeProgram
                        }
                    }
                    recentActivity
                }
                .padding(.horizontal, wide ? 21 : 14)
                .padding(.vertical, 16)
                .frame(maxWidth: 1520)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            }
        }
        .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
         .onChange(of: scenePhase) { _, phase in
            if phase == .active, focusedPlanningDate == nil,
               abs(selectedWeekDate.timeIntervalSinceNow) < 86_400 {
                selectedWeekDate = .now
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

    /// A quiet title area, not another row of summary cards. Weekly
    /// metrics already belong to This Week and Training Development.
    private func heading(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("ATHLTH STUDIO", "ATHLTH STUDIO"))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(ATHLTHStudioStyle.gold)

                    Text(tr("Your training today", "Treningen din i dag"))
                        .font(.system(size: wide ? 30 : 25, weight: .semibold,
                                      design: .rounded))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(Date.now.formatted(
                        .dateTime.weekday(.wide).day().month(.wide)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    focusedPlanningDate =
                        Calendar.current.startOfDay(for: .now)
                } label: {
                    Label(tr("Plan workout", "Planlegg økt"),
                          systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHStudioStyle.ink)
                .accessibilityHint(tr(
                    "Opens the iPad planner with the week vertically at left",
                    "Åpner planlegging med ukedagene loddrett til venstre"
                ))

                Menu {
                    Button(action: onStartQuick) {
                        Label(tr("Start workout now", "Start økt nå"),
                              systemImage: "play.fill")
                    }
                    Button(action: onOpenPlanner) {
                        Label(tr("Open Plan Studio", "Åpne Plan Studio"),
                              systemImage: "calendar")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(tr("More workout actions",
                                       "Flere treningshandlinger"))
                .buttonStyle(.bordered)
            }

        }
        .padding(.vertical, 1)
        .accessibilityIdentifier("athlth-ipad-training-command-header")
    }

    private var headerProgramTitle: String {
        headerProgram?.title ??
            tr("Create a training plan", "Opprett treningsplan")
    }

    private var headerProgramSubtitle: String {
        guard let plan = headerProgram else {
            return tr("Get started in Plan Studio",
                      "Kom i gang i Plan Studio")
        }

        let progress = session.trainingPlanProgress(
            plan,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        if progress.totalSessions > 0 &&
           progress.completedSessions == progress.totalSessions {
            return tr("All planned workouts completed",
                      "Alle planøkter gjennomført")
        }
        switch session.trainingPlanStatus(plan) {
        case .active:
            return weekLabel(for: plan)
        case .upcoming:
            if let start = plan.startDate {
                return tr("Starts", "Starter") + " " +
                    start.formatted(.dateTime.day().month(.abbreviated))
            }
            return tr("Upcoming program", "Kommende plan")
        case .completed:
            return tr("Plan period ended", "Planperioden avsluttet")
        case .unscheduled:
            return tr("Dates not set", "Datoer ikke angitt")
        }
    }

    private func recordedTimeTitle(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let hours = minutes / 60
        let rest = minutes % 60
        return tr("\(hours) h \(rest) min", "\(hours) t \(rest) min")
    }

    private func commandCard(
        label: String,
        title: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(ATHLTHStudioStyle.gold.opacity(0.75))
                }

                Text(title)
                    .font(.system(.headline, design: .rounded,
                                  weight: .semibold))
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 75,
                   alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color.white,
                        in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(ATHLTHStudioStyle.outline.opacity(0.55))
            }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func todayCard(_ next: ATHLTHStudioSchedule.Occurrence?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(
                    tr("YOUR NEXT SESSION", "DIN NESTE ØKT"),
                    systemImage: "calendar.badge.clock"
                )
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                Spacer()
                if let next {
                    Text(Calendar.current.isDateInToday(next.date)
                         ? tr("Today", "I dag")
                         : next.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            ATHLTHStudioStyle.paper,
                            in: Capsule()
                        )
                }
            }

            if let next {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: next.workout.kind.systemImage)
                        .font(.title2)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                        .frame(width: 37, height: 37)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11))

                    Text(next.workout.title)
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                        .lineLimit(2)

                    HStack(spacing: 7) {
                        Text(next.workout.kind.title)
                        if let minutes = next.workout.durationMinutes {
                            Text("· \(minutes) min")
                        }
                        if let distance = next.workout.targetDistanceKilometers,
                           distance > 0 {
                            Text("· \(distance.formatted(.number.precision(.fractionLength(1)))) km")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                    if let planName = next.planTitle {
                        Text(planName)
                            .font(.caption)
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: session.trainingPlans.isEmpty
                          ? "calendar.badge.plus" : "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(ATHLTHStudioStyle.gold)

                    Text(tr("Your next workout starts here", "Din neste økt starter her"))
                        .font(.system(.title, design: .rounded, weight: .semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)

                    Text(tr(
                        "Choose a day below to plan a single session. Build a multi-week program in Plan Studio when you're ready.",
                        "Velg en dag nedenfor for å planlegge én økt. Bygg et program over flere uker i Plan Studio når du ønsker det."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button {
                    if let next {
                        if canStartFromStudio(next) {
                            onStartWorkout(next)
                        } else {
                            onOpenWorkout(next)
                        }
                    } else {
                        focusedPlanningDate = Calendar.current.startOfDay(for: .now)
                    }
                } label: {
                    Label(
                        next == nil
                            ? tr("Plan a workout", "Planlegg en økt")
                            : next.map(canStartFromStudio) == true
                                ? tr("Start workout", "Start økt")
                                : tr("Open workout", "Åpne økten"),
                        systemImage: next == nil ? "calendar.badge.plus"
                            : next.map(canStartFromStudio) == true
                                ? "play.fill" : "arrow.up.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHStudioStyle.ink)
                .contextMenu {
                    if let next {
                        plannedWorkoutContextActions(next)
                    }
                }

                Button(action: onOpenPlanner) {
                    Label(tr("Plan Studio", "Plan Studio"), systemImage: "calendar")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity, minHeight: 267, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 0.98, green: 0.96, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(ATHLTHStudioStyle.gold.opacity(0.37), lineWidth: 1)
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(
                    tr("TRAINING SIGNALS", "TRENINGSIGNALER"),
                    systemImage: "waveform.path.ecg"
                )
                .font(.caption.weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                Spacer()
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            if health.isRefreshing && health.lastSuccessfulRefreshAt == nil {
                ProgressView(tr(
                    "Loading training signals", "Henter treningssignaler"
                ))
                .frame(maxWidth: .infinity, minHeight: 140)
                Spacer(minLength: 0)
            } else if healthHasDataAccess, let score = health.recovery.score {
                HStack(alignment: .center, spacing: 19) {
                    ZStack {
                        Circle()
                            .stroke(ATHLTHStudioStyle.gold.opacity(0.12), lineWidth: 7)

                        Circle()
                            .trim(
                                from: 0,
                                to: CGFloat(max(0, min(score, 100))) / 100
                            )
                            .stroke(
                                ATHLTHStudioStyle.gold,
                                style: StrokeStyle(lineWidth: 7, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 1) {
                            Text("\(score)")
                                .font(.system(size: 34, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(ATHLTHStudioStyle.ink)
                            Text("/ 100")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 118, height: 118)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(tr(
                        "Training signal \(score) of 100",
                        "Treningssignal \(score) av 100"
                    ))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(readinessTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ATHLTHStudioStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(
                            tr("Sleep · HRV · Resting heart rate",
                               "Søvn · HRV · Hvilepuls"),
                            systemImage: "waveform.path.ecg"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(tr(
                    "A locally calculated signal from sleep, HRV and resting heart rate. Not a medical assessment.",
                    "Beregnet lokalt fra søvn, HRV og hvilepuls. Ikke en medisinsk vurdering."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
                Button {
                    showingReadinessExplanation = true
                } label: {
                    Label(
                        tr("Understand your signals", "Forstå signalene"),
                        systemImage: "arrow.up.right"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            } else {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 33, weight: .light))
                    .foregroundStyle(ATHLTHStudioStyle.gold)
                Text(tr("Your signals, when available", "Dine signaler, når de er tilgjengelige"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(healthHasDataAccess
                     ? tr(
                        "We're still gathering enough measurements for a personal baseline.",
                        "Vi samler fortsatt målinger for å finne din personlige normal."
                       )
                     : tr(
                        "Apple Health isn't available or hasn't been connected on this iPad.",
                        "Apple Health er ikke tilgjengelig eller er ikke koblet til på denne iPaden."
                       ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    if healthHasDataAccess {
                        onOpenInsights()
                    } else {
                        onOpenSettings()
                    }
                } label: {
                    Label(
                        healthHasDataAccess
                            ? tr("View insights", "Se innsikt")
                            : tr("Health settings", "Helseinnstillinger"),
                        systemImage: "arrow.up.right"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
            }
        }
        .padding(21)
        .frame(maxWidth: .infinity, minHeight: 267, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Color.white, ATHLTHStudioStyle.paper],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(ATHLTHStudioStyle.gold.opacity(0.24))
        }
    }

    private var readinessTitle: String {
        switch health.recovery.state {
        case .ready:
            tr("Strong recovery signal", "Gode restitusjonssignaler")
        case .balanced:
            tr("Balanced signals", "Balanserte signaler")
        case .takeItEasy:
            tr("Consider a lighter day", "Vurder en lettere dag")
        case .recover:
            tr("Recovery may need attention", "Restitusjon kan trenge oppmerksomhet")
        case .buildingBaseline:
            tr("Building your baseline", "Bygger din normal")
        }
    }

    private func weekCard(
        _ currentWeek: ATHLTHStudioHomeWeek.Snapshot,
        width: CGFloat
    ) -> some View {
        let today = Date.now
        let selected = currentWeek.days.first {
            Calendar.current.isDate($0.date, inSameDayAs: selectedWeekDate)
        } ?? currentWeek.days.first
        // Seven cards fit without sideways scrolling in regular-width
        // landscape. Narrow Stage Manager windows scroll horizontally.
        let cardWidth = max(96, (width - 138) / 7)

        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("This week", "Denne uken"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                    Text(
                        ATHLTHStudioHomeWeek.weekRange(
                            containing: selectedWeekDate
                        ).start.formatted(.dateTime.day().month(.abbreviated)) +
                        " – " +
                        ATHLTHStudioHomeWeek.weekRange(
                            containing: selectedWeekDate
                        ).end.formatted(.dateTime.day().month(.abbreviated))
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(healthHasDataAccess
                         ? "\(currentWeek.plannedCount) " +
                            tr("planned", "planlagte") + " · " +
                            "\(currentWeek.recordedCount) " +
                            tr("recorded", "registrerte")
                         : "\(currentWeek.plannedCount) " +
                            tr("planned", "planlagte") + " · " +
                            tr("Health history unavailable", "Helsehistorikk mangler")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Button {
                        shiftWeek(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(tr("Previous week", "Forrige uke"))

                    Button {
                        selectedWeekDate = .now
                    } label: {
                        Text(tr("Today", "I dag"))
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel(tr("Go to current week", "Gå til denne uken"))

                    Button {
                        shiftWeek(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(tr("Next week", "Neste uke"))
                }
                .buttonStyle(.borderless)

                Button(action: onOpenPlanner) {
                    Label(tr("See plan", "Se planen"), systemImage: "arrow.up.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                .font(.subheadline.weight(.semibold))
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(currentWeek.days) { day in
                        weekDayButton(
                            day,
                            today: today,
                            selected: selected.map {
                                Calendar.current.isDate(day.date, inSameDayAs: $0.date)
                            } ?? false
                        )
                        .frame(width: cardWidth)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selected.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHStudioStyle.ink)
                        Spacer()
                        if healthHasDataAccess {
                            Text("\(selected.recorded.count) " +
                                 tr("recorded", "registrerte"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if selected.planned.isEmpty && selected.recorded.isEmpty {
                        Label(
                            tr("No workouts on this day", "Ingen økter denne dagen"),
                            systemImage: "calendar"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 32, alignment: .leading)
                    } else {
                        ForEach(selected.planned.prefix(3)) { entry in
                            Button {
                                if canStartFromStudio(entry) {
                                    onStartWorkout(entry)
                                } else {
                                    onOpenWorkout(entry)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: entry.workout.kind.systemImage)
                                        .foregroundStyle(ATHLTHStudioStyle.gold)
                                        .frame(width: 25)
                                    Text(entry.workout.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(ATHLTHStudioStyle.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 5)
                                    if isRecordedCompleted(entry) {
                                        Label(
                                            tr("Completed", "Utført"),
                                            systemImage: "checkmark.circle.fill"
                                        )
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ATHLTHStudioStyle.gold)
                                    } else if let duration = entry.workout.durationMinutes {
                                        Text("\(duration) min")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if canStartFromStudio(entry) {
                                        Text(tr("Start", "Start"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(ATHLTHStudioStyle.gold)
                                    }
                                    Image(systemName: canStartFromStudio(entry)
                                          ? "play.circle.fill" : "arrow.up.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ATHLTHStudioStyle.gold)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(canStartFromStudio(entry)
                                ? tr("Tap to start; hold for Watch or delayed start",
                                     "Trykk for å starte; hold for Watch eller utsatt start")
                                : tr("Open workout details", "Åpne øktdetaljer")
                            )
                            .contextMenu {
                                plannedWorkoutContextActions(entry)
                            }
                        }
                        if selected.planned.count > 3 {
                            Button {
                                onOpenPlanner()
                            } label: {
                                Text("+ \(selected.planned.count - 3) " +
                                     tr("more – open Plan Studio", "til – åpne Plan Studio"))
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                        }

                        if healthHasDataAccess {
                            ForEach(selected.recorded) { recorded in
                                Button {
                                    onInspect(recorded)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(ATHLTHStudioStyle.gold)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recorded.activity.rawValue)
                                                .font(.subheadline.weight(.medium))
                                            Text(recorded.startDate.formatted(
                                                date: .omitted, time: .shortened
                                            ))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 4)
                                        Text("\(Int(recorded.duration / 60)) min")
                                            .font(.caption)
                                        Text(tr("Recorded", "Registrert"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(ATHLTHStudioStyle.gold)
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(ATHLTHStudioStyle.ink)
                                    .frame(minHeight: 42)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        focusedPlanningDate = selected.date
                    } label: {
                        Label(
                            tr("Plan a workout", "Planlegg økt"),
                            systemImage: "plus.circle"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHStudioStyle.ink)
                    .disabled(
                        !HomeWeeklyProgressCalendar.canScheduleStandalone(
                            on: selected.date
                        )
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    ATHLTHStudioStyle.canvas,
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
        .padding(20)
        .background(ATHLTHStudioStyle.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.55))
        }
    }

    private func canStartFromStudio(
        _ entry: ATHLTHStudioSchedule.Occurrence
    ) -> Bool {
        guard let planID = entry.planID,
              !entry.workout.isExplicitRestDay,
              !session.isPlanSessionSkipped(
                  planID: planID, sessionID: entry.workout.id
              ),
              !isRecordedCompleted(entry)
        else { return false }
        return true
    }

    @ViewBuilder
    private func plannedWorkoutContextActions(
        _ entry: ATHLTHStudioSchedule.Occurrence
    ) -> some View {
        if canStartFromStudio(entry) {
            Button {
                onStartWorkout(entry)
            } label: {
                Label(tr("Start workout", "Start økt"), systemImage: "play.fill")
            }
            if [.running, .walking, .strength].contains(entry.workout.kind) {
                Button {
                    onSendToWatch(entry)
                } label: {
                    Label(tr("Send to Apple Watch", "Send til Apple Watch"),
                          systemImage: "applewatch")
                }
            }
            Menu {
                Button(tr("In 5 minutes", "Om 5 minutter")) {
                    onStartAfter(entry, 5 * 60)
                }
                Button(tr("In 15 minutes", "Om 15 minutter")) {
                    onStartAfter(entry, 15 * 60)
                }
                Button(tr("In 30 minutes", "Om 30 minutter")) {
                    onStartAfter(entry, 30 * 60)
                }
            } label: {
                Label(tr("Start later", "Start senere"), systemImage: "clock")
            }
        }
        Button {
            onOpenWorkout(entry)
        } label: {
            Label(tr("Workout details", "Øktdetaljer"), systemImage: "info.circle")
        }
    }

    private func weekDayButton(
        _ day: ATHLTHStudioHomeWeek.Day,
        today: Date,
        selected: Bool
    ) -> some View {
        let isToday = Calendar.current.isDate(day.date, inSameDayAs: today)
        return Button {
            selectedWeekDate = day.date
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption.weight(.medium))
                    Spacer()
                    if isToday {
                        Circle()
                            .fill(ATHLTHStudioStyle.gold)
                            .frame(width: 6, height: 6)
                    }
                }

                Text(day.date.formatted(.dateTime.day()))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()

                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text("\(day.planned.count)")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                    Image(systemName: !day.recorded.isEmpty
                          ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(!day.recorded.isEmpty
                            ? ATHLTHStudioStyle.gold : Color.secondary)
                    Text(healthHasDataAccess ? "\(day.recorded.count)" : "—")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(selected ? ATHLTHStudioStyle.ink : .secondary)
            }
            .foregroundStyle(ATHLTHStudioStyle.ink)
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 103, alignment: .topLeading)
            .background(
                selected
                    ? ATHLTHStudioStyle.canvas
                    : ATHLTHStudioStyle.paper,
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        selected ? ATHLTHStudioStyle.gold :
                            ATHLTHStudioStyle.outline.opacity(0.5),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            day.date.formatted(date: .complete, time: .omitted) + ", " +
            "\(day.planned.count) " + tr("planned", "planlagte") + ", " +
            (healthHasDataAccess
                ? "\(day.recorded.count) " + tr("recorded", "registrerte")
                : tr("Health history unavailable", "Helsehistorikk mangler"))
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func shiftWeek(_ amount: Int) {
        selectedWeekDate = ATHLTHStudioHomeWeek.shiftedWeek(
            from: selectedWeekDate, offset: amount
        )
    }

    /// Only the plan's own completion identity may mark a scheduled
    /// workout completed. A random HealthKit recording on the same date
    /// must never silently complete a plan session.
    private func isRecordedCompleted(
        _ entry: ATHLTHStudioSchedule.Occurrence
    ) -> Bool {
        guard let planID = entry.planID else { return false }
        return session.isPlanSessionCompleted(
            planID: planID, sessionID: entry.workout.id,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
    }

    private var trainingDevelopment: some View {
        let data = snapshot
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Training development", "Treningsutvikling"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                    Text(tr(
                        "Recorded training time from Apple Health",
                        "Registrert treningstid fra Apple Health"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 5)
                Picker(tr("Period", "Periode"), selection: $periodDays) {
                    Text("7").tag(7)
                    Text("28").tag(28)
                    Text("90").tag(90)
                }
                .pickerStyle(.segmented)
                .frame(width: 155)
                .accessibilityLabel(tr("Number of days", "Antall dager"))
            }

            if health.isRefreshing && health.lastSuccessfulRefreshAt == nil {
                ProgressView(tr(
                    "Loading workouts from Apple Health",
                    "Henter økter fra Apple Health"
                ))
                .frame(maxWidth: .infinity, minHeight: 165)
            } else if healthHasDataAccess, data.sessions > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Label("\(data.sessions) " + tr("workouts", "økter"), systemImage: "checkmark.circle")
                    Label(
                        String(format: "%.1f t", data.minutes / 60),
                        systemImage: "clock"
                    )
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ATHLTHStudioStyle.ink)

                Chart(data.days) { day in
                    BarMark(
                        x: .value("Date", day.date, unit: .day),
                        y: .value("Hours", day.minutes / 60)
                    )
                    .foregroundStyle(ATHLTHStudioStyle.gold.gradient)
                    .cornerRadius(3)
                }
                .frame(height: 132)
                .accessibilityLabel(tr(
                    "Recorded training duration per day",
                    "Registrert treningstid per dag"
                ))
            } else {
                HStack(spacing: 11) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title2)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tr(
                            "No recorded sessions available for this period",
                            "Ingen registrerte økter tilgjengelige i perioden"
                        ))
                        .font(.subheadline.weight(.medium))
                        Text(healthHasDataAccess
                            ? tr(
                                "Your history will appear when workout data becomes available.",
                                "Historikken vises når treningsdata blir tilgjengelige."
                              )
                            : tr(
                                "Apple Health must be available and connected to show this chart.",
                                "Apple Health må være tilgjengelig og koblet til for å vise grafen."
                              ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            }

            Button(action: onOpenInsights) {
                Label(
                    tr("Explore your training history", "Utforsk treningsutviklingen"),
                    systemImage: "arrow.up.right"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(ATHLTHStudioStyle.gold)
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHStudioStyle.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.55))
        }
    }

    private var activeProgram: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(
                    tr("YOUR PROGRAM", "DITT TRENINGSPROGRAM"),
                    systemImage: "square.stack"
                )
                .font(.caption.weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                Spacer()
            }

            if let plan = currentProgram {
                let progress = session.trainingPlanProgress(
                    plan,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                )

                Text(plan.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                    .lineLimit(2)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(weekLabel(for: plan))
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    Text("\(progress.completedSessions) / \(progress.totalSessions)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)

                GeometryReader { geometry in
                    Capsule()
                        .fill(ATHLTHStudioStyle.canvas)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(ATHLTHStudioStyle.gold)
                                .frame(
                                    width: geometry.size.width *
                                        (progress.totalSessions > 0
                                         ? min(1, Double(progress.completedSessions) /
                                             Double(progress.totalSessions))
                                         : 0)
                                )
                        }
                }
                .frame(height: 7)
                .accessibilityLabel(tr("Program progress", "Fremdrift i programmet"))

                Text(progress.totalSessions == 0
                     ? tr(
                        "The plan does not contain workouts yet.",
                        "Planen inneholder ingen treningsøkter ennå."
                       )
                     : tr(
                        "Completed according to matched or confirmed sessions.",
                        "Fullført basert på koblede eller bekreftede økter."
                       ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Image(systemName: "books.vertical")
                    .font(.title2)
                    .foregroundStyle(ATHLTHStudioStyle.gold)
                Text(tr("Your training library", "Ditt treningsbibliotek"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                Text(tr(
                    "\(session.savedWorkoutTemplates.count) saved workouts ready to reuse. Discover workouts, exercises, routes and plans.",
                    "\(session.savedWorkoutTemplates.count) lagrede økter klare til gjenbruk. Finn økter, øvelser, ruter og planer."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: currentProgram == nil ? onOpenLibrary : onOpenPlanner) {
                Label(
                    currentProgram == nil
                        ? tr("Open library", "Åpne biblioteket")
                        : tr("Open Plan Studio", "Åpne Plan Studio"),
                    systemImage: "arrow.up.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        .background(ATHLTHStudioStyle.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.55))
        }
    }

    private func weekLabel(for plan: TrainingPlan) -> String {
        guard let startDate = plan.startDate, !plan.weeks.isEmpty else {
            return tr("Program dates unavailable", "Planen mangler datoer")
        }
        let calendar = Calendar.current
        let elapsed = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: .now)
        ).day ?? 0
        let weekIndex = max(0, min(plan.weeks.count - 1, elapsed / 7))
        return tr(
            "Week \(weekIndex + 1) of \(plan.weeks.count)",
            "Uke \(weekIndex + 1) av \(plan.weeks.count)"
        )
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("Recent activity", "Siste aktivitet"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                Spacer()
                Button(action: onOpenHistory) {
                    Label(tr("All history", "Hele historikken"), systemImage: "arrow.up.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ATHLTHStudioStyle.gold)
                .font(.subheadline.weight(.semibold))
            }

            if !healthHasDataAccess || recent.isEmpty {
                Text(tr(
                    "No workout history is available on this device yet.",
                    "Ingen treningshistorikk er tilgjengelig på denne enheten ennå."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
            } else {
                ForEach(recent) { workout in
                    Button {
                        onInspect(workout)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: activityIcon(workout.activity))
                                .foregroundStyle(ATHLTHStudioStyle.gold)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(workout.activity.rawValue)
                                    .font(.subheadline.weight(.medium))
                                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(workout.duration / 60)) min")
                                .font(.subheadline)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ATHLTHStudioStyle.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.55))
        }
    }

    private func activityIcon(_ activity: WorkoutActivity) -> String {
        switch activity {
        case .running: "figure.run"
        case .walking, .hiking: "figure.walk"
        case .cycling: "bicycle"
        case .strength: "dumbbell"
        default: "figure.mixed.cardio"
        }
    }
}
