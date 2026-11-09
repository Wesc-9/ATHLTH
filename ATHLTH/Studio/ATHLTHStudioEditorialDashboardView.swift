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
    @State private var remoteStrengthStatus: ATHLTHPrivateLiveStrengthSnapshot?
    @State private var remoteGhostStatus: ATHLTHPrivateGhostSpectatorSnapshot?

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
            guard ATHLTHStudioSchedule.isUpcoming(item) else { return false }
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
            recorded: recordedWorkouts,
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

                        // The other device owns Ghost Race recording.
                        // iPad offers a wide, read-only live course surface.
                        if let remoteGhostStatus, remoteGhostStatus.isFresh() {
                            ATHLTHStudioPrivateGhostSpectatorCard(
                                snapshot: remoteGhostStatus
                            )
                        }

                        // Live workout data is displayed, never edited, on iPad.
                        if strength.activeWorkout != nil {
                            ATHLTHStudioLiveStrengthReadOnlyCard()
                        } else if let remoteStrengthStatus,
                                  remoteStrengthStatus.isFresh() {
                            ATHLTHStudioRemoteStrengthStatusCard(
                                snapshot: remoteStrengthStatus
                            )
                        }

                        // Preserve the approved warm-white Studio appearance.
                        // The week calendar keeps the entire content width.
                        if threeColumns {
                            HStack(alignment: .top, spacing: 15) {
                                planCard
                                    .frame(maxWidth: .infinity)
                                nextWorkoutCard
                                    .frame(width: max(260, width * 0.26))
                                compactReadinessCard
                                    .frame(width: max(220, width * 0.22))
                            }
                        } else if split {
                            HStack(alignment: .top, spacing: 15) {
                                planCard.frame(maxWidth: .infinity)
                                nextWorkoutCard.frame(width: max(270, width * 0.31))
                            }
                            compactReadinessCard
                        } else {
                            planCard
                            nextWorkoutCard
                            compactReadinessCard
                        }

                        weekCard(calendarWeek, width: width)

                        // Coach already lives in the toolbar. Prioritize
                        // factual progress rather than repeated advice.
                        progressCard(wide: split)
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
        .task(id: session.profile.userID) {
            guard ATHLTHDeviceRole.isIPad else { return }
            while !Task.isCancelled {
                if session.signedIn, scenePhase == .active {
                    let account = session.profile.userID
                    let fetched =
                        await ATHLTHPrivateLiveStrengthStatusStore.fetch(
                            for: account
                        )
                    guard !Task.isCancelled,
                          account == session.profile.userID else { return }
                    remoteStrengthStatus = fetched
                } else {
                    remoteStrengthStatus = nil
                }
                try? await Task.sleep(for: .seconds(12))
            }
        }
        .task(id: session.profile.userID) {
            guard ATHLTHDeviceRole.isIPad else { return }
            // Do not briefly show the previous signed-in account's map.
            remoteGhostStatus = nil
            while !Task.isCancelled {
                if session.signedIn, scenePhase == .active {
                    let userID = session.profile.userID
                    let fetched = await ATHLTHPrivateGhostSpectatorStore.fetch(
                        for: userID
                    )
                    guard !Task.isCancelled, userID == session.profile.userID
                    else { return }
                    remoteGhostStatus = fetched
                } else {
                    remoteGhostStatus = nil
                }
                try? await Task.sleep(
                    for: .seconds(remoteGhostStatus == nil ? 8 : 3)
                )
            }
        }
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
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline))
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
            HStack(spacing: 9) {
                Image(systemName: activeDay?.restDays.isEmpty == false
                      ? "moon.zzz" : "calendar.badge.clock")
                    .foregroundStyle(bronze)
                Text(weekSelectionSummary(activeDay))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(bronze)
                    .accessibilityIdentifier("athlth-ipad-week-plan-selected-day")
                }
            }
            .frame(minHeight: 44)
            .padding(.top, 2)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline))
        .accessibilityIdentifier("athlth-ipad-weekly-overview")
    }

    private func weekSelectionSummary(
        _ day: ATHLTHStudioHomeWeek.Day?
    ) -> String {
        guard let day else {
            return tr("Select a day in the calendar",
                      "Velg en dag i kalenderen")
        }
        if !day.planned.isEmpty && !day.recorded.isEmpty {
            return "\(day.planned.count) " + tr("planned", "planlagt") +
                " · \(day.recorded.count) " + tr("recorded", "registrert")
        }
        if !day.planned.isEmpty {
            return "\(day.planned.count) " +
                tr("planned workouts", "planlagte økter")
        }
        if !day.restDays.isEmpty {
            return tr("Planned rest day", "Planlagt hviledag")
        }
        if !day.recorded.isEmpty {
            return "\(day.recorded.count) " +
                tr("recorded workouts", "registrerte økter")
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
        let isPlanCompleted = !day.planned.isEmpty &&
            day.planned.allSatisfy(completed)
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
            onSelectWeekDay(day.date)
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
                if day.planned.count > 1 {
                    Text("\(day.recorded.count) " +
                         tr("recorded", "registrert"))
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
            "Show this day's workouts in the right sidebar",
            "Vis dagens økter i høyre sidepanel"
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

    private func progressCard(wide: Bool) -> some View {
        let data = ATHLTHStudioAnalytics.snapshot(
            from: recordedWorkouts,
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

            if health.isRefreshing && health.lastSuccessfulRefreshAt == nil &&
               strength.workoutHistory.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 125)
            } else if data.sessions > 0 {
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
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(outline))
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
