import SwiftUI
import Charts

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
    let onOpenCoach: () -> Void
    @Binding var focusedPlanningDate: Date?

    @State private var selectedDate = Date.now
    @State private var periodDays = 28
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

    private var program: TrainingPlan? {
        if let active = session.activePlan,
           !session.pausedTrainingPlanIDs.contains(active.id),
           !session.deactivatedTrainingPlanIDs.contains(active.id) {
            return active
        }
        return session.nextTrainingPlan
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
        upcoming.first { item in
            guard let planID = item.planID else { return true }
            return !session.isPlanSessionSkipped(planID: planID, sessionID: item.workout.id)
                && !completed(item)
                && !item.workout.isExplicitRestDay
        }
    }

    private var calendarWeek: ATHLTHStudioHomeWeek.Snapshot {
        ATHLTHStudioHomeWeek.make(
            plans: session.trainingPlans,
            standalone: session.standalonePlannedSessions,
            recorded: hasHealth ? health.workouts : [],
            pausedPlanIDs: session.pausedTrainingPlanIDs,
            deactivatedPlanIDs: session.deactivatedTrainingPlanIDs,
            now: selectedDate
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
                let width = geometry.size.width
                let split = width >= 730 && !dynamicTypeSize.isAccessibilitySize
                let threeColumns = width >= 1040 && !dynamicTypeSize.isAccessibilitySize

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        titleRow(expanded: split)

                        // Live workout data is displayed, never edited, on iPad.
                        if strength.activeWorkout != nil {
                            ATHLTHStudioLiveStrengthReadOnlyCard()
                        }

                        if split {
                            HStack(alignment: .top, spacing: 15) {
                                planCard
                                    .frame(maxWidth: .infinity)
                                nextWorkoutCard
                                    .frame(width: max(280, width * 0.30))
                            }
                        } else {
                            planCard
                            nextWorkoutCard
                        }

                        weekCard(calendarWeek, width: width)

                        if threeColumns {
                            HStack(alignment: .top, spacing: 15) {
                                progressCard.frame(maxWidth: .infinity)
                                signalsCard.frame(maxWidth: .infinity)
                                coachCard.frame(maxWidth: .infinity)
                            }
                        } else if split {
                            HStack(alignment: .top, spacing: 15) {
                                progressCard.frame(maxWidth: .infinity)
                                signalsCard.frame(maxWidth: .infinity)
                            }
                            coachCard
                        } else {
                            progressCard
                            signalsCard
                            coachCard
                        }
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
            if phase == .active,
               focusedPlanningDate == nil,
               abs(selectedDate.timeIntervalSinceNow) < 86_400 {
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("ATHLTH")
                    .font(.system(size: expanded ? 36 : 29, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .tracking(1.2)
                Text("Studio")
                    .font(.system(size: expanded ? 35 : 28, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(bronze)
                Spacer(minLength: 6)
            }
            Text(tr("Your training space", "Ditt treningsrom"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button {
                    focusedPlanningDate = Calendar.current.startOfDay(for: .now)
                } label: {
                    Label(tr("Plan workout", "Planlegg økt"), systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .tint(ink)
                .controlSize(.large)

                Button(action: onStartQuick) {
                    Label(tr("Start workout", "Start økt"), systemImage: "figure.run")
                }
                .buttonStyle(.borderedProminent)
                .tint(ink)
                .controlSize(.large)
            }
        }
        .padding(.bottom, 4)
        .accessibilityIdentifier("athlth-ipad-training-command-header")
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

    private var nextWorkoutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Next workout", "Neste økt"))
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(ink)
            if let item = nextWorkout {
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
                .tint(bronze)
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
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline))
    }

    private func weekCard(_ week: ATHLTHStudioHomeWeek.Snapshot,
                          width: CGFloat) -> some View {
        let activeDay = week.days.first {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        } ?? week.days.first
        let tileWidth = max(88, (width - 92) / 7)

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
                Button { selectedDate = .now } label: {
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

            if let activeDay {
                HStack(spacing: 12) {
                    if let item = activeDay.planned.first,
                       !item.workout.isExplicitRestDay {
                        Image(systemName: item.workout.kind.systemImage)
                            .foregroundStyle(bronze)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.workout.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                            Text(item.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button {
                            openOrStart(item)
                        } label: {
                            Label(
                                canStart(item) ? tr("Start", "Start")
                                    : tr("Open workout", "Åpne økt"),
                                systemImage: canStart(item) ? "play.fill" : "arrow.up.right"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(ink)
                        .contextMenu { workoutActions(item) }
                    } else {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(bronze)
                        Text(activeDay.planned.first?.workout.isExplicitRestDay == true
                             ? tr("Rest day", "Hviledag")
                             : tr("No workout planned", "Ingen planlagt økt"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button {
                            focusedPlanningDate = activeDay.date
                        } label: {
                            Label(tr("Plan a workout", "Planlegg økt"),
                                  systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!HomeWeeklyProgressCalendar.canScheduleStandalone(
                            on: activeDay.date
                        ))
                    }
                }
                .frame(minHeight: 47)
                .padding(.top, 10)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline))
        .accessibilityIdentifier("athlth-ipad-weekly-overview")
    }

    private func dayTile(_ day: ATHLTHStudioHomeWeek.Day,
                         selected: Bool) -> some View {
        let planned = day.planned.first
        let isToday = Calendar.current.isDateInToday(day.date)
        let isRest = planned?.workout.isExplicitRestDay == true

        return Button {
            selectedDate = day.date
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
                Image(systemName: planned == nil ? (!day.recorded.isEmpty
                    ? "checkmark.circle.fill" : "minus") :
                    isRest ? "moon.zzz" : planned!.workout.kind.systemImage)
                    .font(.system(size: 21))
                    .frame(height: 26)
                Text(planned == nil
                     ? (!day.recorded.isEmpty
                        ? tr("Recorded", "Registrert")
                        : tr("No workout", "Ingen økt"))
                     : isRest ? tr("Rest", "Hvile") : planned!.workout.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32, alignment: .top)
                if let item = planned,
                   !isRest,
                   let minutes = item.workout.durationMinutes {
                    Text("\(minutes) min")
                        .font(.caption)
                        .opacity(0.8)
                } else {
                    Text(" ").font(.caption)
                }
            }
            .foregroundStyle(selected ? Color.white : ink)
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 153, alignment: .topLeading)
            .background(
                selected ? ink : cream,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            day.date.formatted(date: .complete, time: .omitted) + ", " +
            (planned?.workout.title ??
                tr("No planned workout", "Ingen planlagt økt"))
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func shiftWeek(_ offset: Int) {
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

    private func canStart(_ item: ATHLTHStudioSchedule.Occurrence) -> Bool {
        guard let planID = item.planID,
              !item.workout.isExplicitRestDay,
              !session.isPlanSessionSkipped(planID: planID, sessionID: item.workout.id),
              !completed(item) else { return false }
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

    private var progressCard: some View {
        let data = ATHLTHStudioAnalytics.snapshot(
            from: hasHealth ? health.workouts : [],
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
                .tint(bronze)
            }
            Text(tr("Recorded training time", "Registrert treningstid"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if health.isRefreshing && health.lastSuccessfulRefreshAt == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 125)
            } else if hasHealth && data.sessions > 0 {
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
                        LinearGradient(colors: [bronze.opacity(0.19), bronze.opacity(0.01)],
                                       startPoint: .top, endPoint: .bottom)
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
                    "Daily recorded training hours", "Registrerte treningstimer per dag"
                ))
            } else {
                ContentUnavailableView(
                    tr("No training data yet", "Ingen treningsdata ennå"),
                    systemImage: "chart.xyaxis.line",
                    description: Text(hasHealth
                        ? tr("Workouts will appear here once recorded.",
                             "Registrerte økter vises her.")
                        : tr("Connect Apple Health to view progress.",
                             "Koble til Apple Health for å se fremgang."))
                )
                .frame(maxWidth: .infinity, minHeight: 141)
            }
            Spacer(minLength: 0)
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
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline))
    }

    private var signalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Training signals", "Treningssignaler"))
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(ink)

            if health.isRefreshing && health.lastSuccessfulRefreshAt == nil {
                ProgressView(tr("Loading health data", "Henter helsedata"))
                    .frame(maxWidth: .infinity, minHeight: 145)
            } else if hasHealth, let score = health.recovery.score {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(outline, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: CGFloat(max(0, min(100, score))) / 100)
                            .stroke(bronze, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(score)")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                    }
                    .frame(width: 98, height: 98)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(readinessTitle)
                            .font(.headline)
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(tr("Sleep · HRV · resting heart rate",
                                "Søvn · HRV · hvilepuls"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(tr(
                    "Calculated from your available measurements. Not a medical assessment.",
                    "Beregnet fra tilgjengelige målinger. Ikke en medisinsk vurdering."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ContentUnavailableView(
                    tr("Signals unavailable", "Signaler utilgjengelige"),
                    systemImage: "heart.text.square",
                    description: Text(hasHealth
                        ? tr("A personal baseline is still being built.",
                             "Vi bygger fortsatt din personlige normal.")
                        : tr("Apple Health is not available or connected.",
                             "Apple Health er ikke tilgjengelig eller tilkoblet."))
                )
                .frame(maxWidth: .infinity, minHeight: 145)
            }

            Spacer(minLength: 0)
            Button {
                if hasHealth {
                    showingReadinessExplanation = true
                } else {
                    onOpenSettings()
                }
            } label: {
                Label(tr("Understand your signals", "Forstå signalene"),
                      systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(bronze)
            .frame(minHeight: 44, alignment: .leading)
        }
        .padding(19)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline))
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

    private var coachMessage: String {
        guard hasHealth, health.recovery.score != nil else {
            return tr(
                "Open Coach to explore your training plan and goals.",
                "Åpne Coach for å utforske treningsplanen og målene dine."
            )
        }
        switch health.recovery.state {
        case .ready, .balanced:
            return tr(
                "Your recovery signals look balanced. Review the planned workout before starting.",
                "Restitusjonssignalene ser balanserte ut. Se over dagens økt før du starter."
            )
        case .takeItEasy, .recover:
            return tr(
                "Your recovery signals suggest a lighter day. Review your training load with Coach.",
                "Restitusjonssignalene kan tilsi en roligere dag. Se over belastningen med Coach."
            )
        case .buildingBaseline:
            return tr(
                "More measurements are needed before assessing recovery trends.",
                "Vi trenger flere målinger før vi kan vurdere restitusjonstrenden."
            )
        }
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("ATHLTH Coach", systemImage: "sparkles")
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(ink)
            Text(tr("Today's perspective", "Dagens vurdering"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(bronze)
            Text(coachMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onOpenCoach) {
                Label(tr("Open Coach", "Åpne Coach"),
                      systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(bronze)
            .frame(minHeight: 44, alignment: .leading)
        }
        .padding(19)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline))
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
