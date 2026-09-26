import SwiftUI

struct AdvancedPlannerView: View {
    @EnvironmentObject private var session: AppSessionStore

    let onOpenPrograms: () -> Void

    @State private var selectedWeekID: UUID?
    @State private var selectedDayID: UUID?
    @State private var selectedWorkout: PlannedSession?
    @State private var showingSessionEditor = false
    @State private var showingPlanEditor = false
    @State private var showingProgramCreation = false

    init(onOpenPrograms: @escaping () -> Void = {}) {
        self.onOpenPrograms = onOpenPrograms
    }

    var body: some View {
        VStack(spacing: 16) {
            if let plan = session.activePlan {
                planOverview(plan)

                if let week = selectedWeek(in: plan) {
                    weekSelector(plan)
                    daySelector(plan, week: week)

                    if let day = selectedDay(in: week) {
                        selectedDayCard(
                            plan: plan,
                            week: week,
                            day: day
                        )
                    }

                    weekOverview(plan, week: week)
                }
            } else {
                emptyPlanState
            }
        }
        .onAppear {
            syncSelection()
        }
        .onChange(of: session.activePlan?.id) { _, _ in
            syncSelection()
        }
        .onChange(of: session.activePlan?.version) { _, _ in
            reconcileSelection()
        }
        .sheet(isPresented: $showingSessionEditor) {
            if let selectedDayID {
                SessionEditorView(dayID: selectedDayID)
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
        .sheet(item: $selectedWorkout) { workout in
            if let planID = session.activePlan?.id {
                PlannedWorkoutDetailView(
                    planID: planID,
                    workout: workout,
                    isHealthCompleted: false
                )
                .environmentObject(session)
            }
        }
    }

    private func planOverview(_ plan: TrainingPlan) -> some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 15)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(planTimelineText(plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !plan.summary
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty {
                        Text(plan.summary)
                            .font(.subheadline)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText.opacity(0.78)
                            )
                            .padding(.top, 2)
                    }
                }

                Spacer()

                Button {
                    showingPlanEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Edit training plan")
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 125), spacing: 10)
                ],
                spacing: 10
            ) {
                plannerMetric(
                    title: "Sessions",
                    value: "\(allSessions(in: plan).count)",
                    icon: "figure.run"
                )

                plannerMetric(
                    title: "Training days",
                    value: "\(trainingDayCount(in: plan))",
                    icon: "calendar"
                )

                plannerMetric(
                    title: "Planned time",
                    value: plannedDurationText(plan),
                    icon: "timer"
                )

                plannerMetric(
                    title: "Run / walk",
                    value: plannedDistanceText(plan),
                    icon: "point.topleft.down.to.point.bottomright.curvepath"
                )
            }
            .padding(.top, 14)
        }
    }

    private func weekSelector(_ plan: TrainingPlan) -> some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weeks")
                        .font(.title3.weight(.bold))
                    Text("Jump between weeks without leaving the planner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    session.addWeekToActivePlan()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(plan.weeks.count >= 52)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(plan.weeks) { week in
                        let selected = selectedWeekID == week.id
                        let count = week.days.reduce(0) {
                            $0 + $1.sessions.count
                        }

                        Button {
                            selectedWeekID = week.id
                            selectBestDay(in: week, plan: plan)
                        } label: {
                            VStack(spacing: 3) {
                                Text("W\(week.weekNumber)")
                                    .font(.subheadline.weight(.bold))

                                Text(
                                    count == 1
                                        ? "1 session"
                                        : "\(count) sessions"
                                )
                                .font(.system(size: 9, weight: .semibold))
                                .opacity(0.78)
                            }
                            .foregroundStyle(
                                selected ? Color.white : ATHLTHTheme.primaryText
                            )
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(
                                selected
                                    ? ATHLTHTheme.accent
                                    : Color.primary.opacity(0.035),
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
                                    selected
                                        ? Color.clear
                                        : Color.black.opacity(0.045),
                                    lineWidth: 1
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .padding(.top, 12)
        }
    }

    private func daySelector(
        _ plan: TrainingPlan,
        week: TrainingPlanWeek
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(week.days) { day in
                    let selected = selectedDayID == day.id
                    let date = date(for: day, in: week, plan: plan)
                    let isToday = date.map(Calendar.current.isDateInToday) ?? false

                    Button {
                        selectedDayID = day.id
                    } label: {
                        VStack(spacing: 5) {
                            Text(
                                shortDayLabel(
                                    day,
                                    week: week,
                                    plan: plan
                                )
                            )
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)

                            Text(
                                date?.formatted(
                                    .dateTime.day()
                                ) ?? "\(day.dayIndex)"
                            )
                            .font(.title3.weight(.bold))

                            HStack(spacing: 3) {
                                if isToday {
                                    Circle()
                                        .fill(
                                            selected
                                                ? Color.white
                                                : ATHLTHTheme.accent
                                        )
                                        .frame(width: 5, height: 5)
                                }

                                Text(
                                    day.sessions.isEmpty
                                        ? "Rest"
                                        : "\(day.sessions.count)"
                                )
                                .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .foregroundStyle(
                            selected ? Color.white : ATHLTHTheme.primaryText
                        )
                        .frame(width: 62, height: 78)
                        .background(
                            selected
                                ? ATHLTHTheme.accent
                                : Color.white.opacity(0.72),
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
                                selected
                                    ? Color.clear
                                    : isToday
                                        ? ATHLTHTheme.accent.opacity(0.34)
                                        : Color.black.opacity(0.045),
                                lineWidth: isToday ? 1.3 : 1
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }

    private func selectedDayCard(
        plan: TrainingPlan,
        week: TrainingPlanWeek,
        day: TrainingPlanDay
    ) -> some View {
        ATHLTHCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        displayDayTitle(
                            day,
                            week: week,
                            plan: plan
                        )
                    )
                    .font(.title3.weight(.bold))

                    Text(daySubtitle(day, week: week, plan: plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    selectedDayID = day.id
                    showingSessionEditor = true
                } label: {
                    Label("Add workout", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(ATHLTHTheme.accent)
            }

            if day.sessions.isEmpty {
                Button {
                    selectedDayID = day.id
                    showingSessionEditor = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(ATHLTHTheme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rest day — or add a workout")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)

                            Text(
                                "Strength, run, walk, mobility and recovery can all be planned here."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(
                        ATHLTHTheme.accentSoft.opacity(0.55),
                        in: RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(day.sessions) { workout in
                        sessionRow(
                            workout,
                            dayID: day.id
                        )
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func weekOverview(
        _ plan: TrainingPlan,
        week: TrainingPlanWeek
    ) -> some View {
        ATHLTHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week at a glance")
                        .font(.title3.weight(.bold))
                    Text("Tap a day to edit its schedule.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(
                    "\(week.days.reduce(0) { $0 + $1.sessions.count }) total"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accent)
            }

            VStack(spacing: 0) {
                ForEach(Array(week.days.enumerated()), id: \.element.id) {
                    index,
                    day in
                    Button {
                        selectedDayID = day.id
                    } label: {
                        HStack(spacing: 12) {
                            Text(
                                shortDayLabel(
                                    day,
                                    week: week,
                                    plan: plan
                                )
                            )
                            .font(.caption.weight(.bold))
                                .foregroundStyle(
                                    selectedDayID == day.id
                                        ? ATHLTHTheme.accent
                                        : ATHLTHTheme.mutedText
                                )
                                .frame(width: 34, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    day.sessions.isEmpty
                                        ? "Rest"
                                        : day.sessions
                                            .map(\.title)
                                            .joined(separator: " · ")
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)
                                .lineLimit(1)

                                if let date = date(
                                    for: day,
                                    in: week,
                                    plan: plan
                                ) {
                                    Text(
                                        date.formatted(
                                            .dateTime
                                                .month(.abbreviated)
                                                .day()
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if !day.sessions.isEmpty {
                                Text("\(day.sessions.count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(ATHLTHTheme.accent)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        ATHLTHTheme.accentSoft,
                                        in: Circle()
                                    )
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption2.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < week.days.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var emptyPlanState: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 13) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 48, height: 48)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 15)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Build your training plan")
                            .font(.title3.weight(.bold))

                        Text(
                            "Start simple, or build an advanced multi-week program with exact workouts, routes, exercises and targets."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        showingProgramCreation = true
                    } label: {
                        Label("Create Plan", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ATHLTHTheme.accent)

                    Button {
                        onOpenPrograms()
                    } label: {
                        Label("Library", systemImage: "square.stack.3d.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func sessionRow(
        _ workout: PlannedSession,
        dayID: UUID
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedWorkout = workout
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: workout.kind.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 12)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(workout.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.primaryText)

                            if let start = workout.scheduledStart {
                                Text(
                                    start.formatted(
                                        date: .omitted,
                                        time: .shortened
                                    )
                                )
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accent)
                            }
                        }

                        Text(sessionSummary(workout))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(11)
                .background(
                    Color.primary.opacity(0.025),
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)

            Menu {
                Button(role: .destructive) {
                    session.removeSession(
                        workout.id,
                        fromDay: dayID
                    )
                } label: {
                    Label("Delete Workout", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 40)
            }
            .buttonStyle(.plain)
        }
    }

    private func plannerMetric(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 30, height: 30)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private func allSessions(
        in plan: TrainingPlan
    ) -> [PlannedSession] {
        plan.weeks
            .flatMap(\.days)
            .flatMap(\.sessions)
    }

    private func trainingDayCount(
        in plan: TrainingPlan
    ) -> Int {
        plan.weeks
            .flatMap(\.days)
            .filter { !$0.sessions.isEmpty }
            .count
    }

    private func plannedDurationText(
        _ plan: TrainingPlan
    ) -> String {
        let minutes = allSessions(in: plan)
            .compactMap(\.durationMinutes)
            .reduce(0, +)

        guard minutes > 0 else { return "—" }

        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0
            ? "\(hours)h"
            : "\(hours)h \(remaining)m"
    }

    private func plannedDistanceText(
        _ plan: TrainingPlan
    ) -> String {
        let distance = allSessions(in: plan)
            .compactMap(\.targetDistanceKilometers)
            .reduce(0, +)

        guard distance > 0 else { return "—" }

        return String(format: "%.1f km", distance)
    }

    private func planTimelineText(
        _ plan: TrainingPlan
    ) -> String {
        guard let start = plan.startDate else {
            return "\(plan.weeks.count) weeks · \(plan.visibility.title)"
        }

        let end = Calendar.current.date(
            byAdding: .day,
            value: max(plan.weeks.count * 7 - 1, 0),
            to: start
        ) ?? start

        return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted)) · \(plan.weeks.count) weeks"
    }

    private func daySubtitle(
        _ day: TrainingPlanDay,
        week: TrainingPlanWeek,
        plan: TrainingPlan
    ) -> String {
        if let date = date(for: day, in: week, plan: plan) {
            return date.formatted(
                .dateTime
                    .weekday(.wide)
                    .month(.wide)
                    .day()
            )
        }

        return "Week \(week.weekNumber) · \(day.sessions.count) planned"
    }

    private func displayDayTitle(
        _ day: TrainingPlanDay,
        week: TrainingPlanWeek,
        plan: TrainingPlan
    ) -> String {
        guard let date = date(
            for: day,
            in: week,
            plan: plan
        ) else {
            return day.title
        }

        let weekday = Calendar.current.component(
            .weekday,
            from: date
        )

        let titles = [
            "Sunday",
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday"
        ]

        guard (1...7).contains(weekday) else {
            return day.title
        }

        return titles[weekday - 1]
    }

    private func shortDayLabel(
        _ day: TrainingPlanDay,
        week: TrainingPlanWeek,
        plan: TrainingPlan
    ) -> String {
        String(
            displayDayTitle(
                day,
                week: week,
                plan: plan
            )
            .prefix(3)
        )
        .uppercased()
    }

    private func date(
        for day: TrainingPlanDay,
        in week: TrainingPlanWeek,
        plan: TrainingPlan
    ) -> Date? {
        guard let startDate = plan.startDate else {
            return nil
        }

        let offset =
            max(week.weekNumber - 1, 0) * 7 +
            max(day.dayIndex - 1, 0)

        return Calendar.current.date(
            byAdding: .day,
            value: offset,
            to: Calendar.current.startOfDay(for: startDate)
        )
    }

    private func selectedWeek(
        in plan: TrainingPlan
    ) -> TrainingPlanWeek? {
        if let selectedWeekID,
           let selected = plan.weeks.first(
                where: { $0.id == selectedWeekID }
           ) {
            return selected
        }

        return bestWeek(in: plan) ?? plan.weeks.first
    }

    private func selectedDay(
        in week: TrainingPlanWeek
    ) -> TrainingPlanDay? {
        if let selectedDayID,
           let selected = week.days.first(
                where: { $0.id == selectedDayID }
           ) {
            return selected
        }

        return week.days.first
    }

    private func bestWeek(
        in plan: TrainingPlan
    ) -> TrainingPlanWeek? {
        guard let startDate = plan.startDate else {
            return plan.weeks.first
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())
        let days = calendar.dateComponents(
            [.day],
            from: start,
            to: today
        ).day ?? 0

        guard days >= 0 else {
            return plan.weeks.first
        }

        let targetNumber = (days / 7) + 1
        return plan.weeks.first {
            $0.weekNumber == targetNumber
        } ?? plan.weeks.last
    }

    private func selectBestDay(
        in week: TrainingPlanWeek,
        plan: TrainingPlan
    ) {
        if let today = week.days.first(
            where: { day in
                guard let date = date(
                    for: day,
                    in: week,
                    plan: plan
                ) else {
                    return false
                }

                return Calendar.current.isDateInToday(date)
            }
        ) {
            selectedDayID = today.id
        } else {
            selectedDayID = week.days.first?.id
        }
    }

    private func syncSelection() {
        guard let plan = session.activePlan,
              let week = bestWeek(in: plan) ?? plan.weeks.first
        else {
            selectedWeekID = nil
            selectedDayID = nil
            return
        }

        selectedWeekID = week.id
        selectBestDay(in: week, plan: plan)
    }

    private func reconcileSelection() {
        guard let plan = session.activePlan else {
            selectedWeekID = nil
            selectedDayID = nil
            return
        }

        guard let week = selectedWeek(in: plan) else {
            syncSelection()
            return
        }

        selectedWeekID = week.id

        if let selectedDayID,
           week.days.contains(where: { $0.id == selectedDayID }) {
            return
        }

        selectBestDay(in: week, plan: plan)
    }

    private func sessionSummary(
        _ workout: PlannedSession
    ) -> String {
        var parts: [String] = []

        if let running = workout.runningWorkout {
            parts.append(running.type.title)
            parts.append("\(running.blocks.count) blocks")
        } else {
            if let duration = workout.durationMinutes {
                parts.append("\(duration) min")
            }

            if let distance = workout.targetDistanceKilometers {
                parts.append(
                    String(format: "%.1f km", distance)
                )
            }
        }

        if !workout.exercises.isEmpty {
            parts.append(
                "\(workout.exercises.count) exercises"
            )
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
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let onOpenCalendar: () -> Void

    @State private var showingPlanEditor = false
    @State private var showingProgramCreation = false
    @State private var programToStart: TrainingPlan?
    @State private var aiMode: AIProgramGenerationMode?
    @State private var showingAISubscriptionOffer = false

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
                        Text("Programs")
                            .font(.title3.weight(.bold))
                        Text(
                            "Create or start a reusable training program. Schedule its workouts in Plan."
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

            ATHLTHCard {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 14)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text("ATHLTH AI")
                                .font(.title3.weight(.bold))

                            if !session.canAccess(.aiTrainingPrograms) {
                                Label("ATHLTH+", systemImage: "lock.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(ATHLTHTheme.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(
                                        ATHLTHTheme.accentSoft,
                                        in: Capsule()
                                    )
                            }
                        }
                        Text(
                            "Generate a program from your goals, dates and available training days — or let AI fill only the gaps in the program you already started."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button {
                                openAI(.generate)
                            } label: {
                                Label(
                                    "Generate",
                                    systemImage: "sparkles"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(ATHLTHTheme.accent)

                            if session.activePlan != nil {
                                Button {
                                    openAI(.complete)
                                } label: {
                                    Label(
                                        "Complete",
                                        systemImage: "wand.and.stars"
                                    )
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.top, 4)

                        if goalStore.activeGoals.isEmpty {
                            Text("Create a goal in Progress first to use goal-based generation.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
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

                        Button("Plan") {
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
        .sheet(item: $aiMode) { mode in
            AIProgramBuilderView(mode: mode)
        }
        .sheet(isPresented: $showingAISubscriptionOffer) {
            SubscriptionOfferView {
                session.applyStoreKitEntitlement(
                    subscriptionStore.activeEntitlement
                )

                if session.canAccess(.aiTrainingPrograms) {
                    showingAISubscriptionOffer = false
                }
            }
            .environmentObject(subscriptionStore)
        }
    }

    private func openAI(_ mode: AIProgramGenerationMode) {
        guard session.canAccess(.aiTrainingPrograms) else {
            showingAISubscriptionOffer = true
            return
        }

        aiMode = mode
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

private enum TrainingPlanCreationMode: String, Identifiable {
    case simple
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simple: return "Simple"
        case .advanced: return "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .simple:
            return "Choose your focus and weekly frequency. ATHLTH creates a useful starting schedule for you."
        case .advanced:
            return "Control timeline, goals, visibility and build every workout exactly the way you want."
        }
    }

    var icon: String {
        switch self {
        case .simple: return "wand.and.stars"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

private enum SimpleTrainingPlanFocus: String, CaseIterable, Identifiable {
    case balanced
    case running
    case strength
    case hybrid
    case walking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .running: return "Running"
        case .strength: return "Strength"
        case .hybrid: return "Hybrid"
        case .walking: return "Walking"
        }
    }

    var subtitle: String {
        switch self {
        case .balanced:
            return "A mix of strength, running and walking"
        case .running:
            return "Running first, with mobility between sessions"
        case .strength:
            return "Strength first, with mobility support"
        case .hybrid:
            return "Alternate strength and running"
        case .walking:
            return "Walking volume with supporting strength"
        }
    }

    var icon: String {
        switch self {
        case .balanced: return "circle.grid.cross"
        case .running: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .hybrid: return "arrow.triangle.2.circlepath"
        case .walking: return "figure.walk"
        }
    }

    var pattern: [WorkoutKind] {
        switch self {
        case .balanced:
            return [.strength, .running, .walking]
        case .running:
            return [.running, .running, .mobility]
        case .strength:
            return [.strength, .strength, .mobility]
        case .hybrid:
            return [.strength, .running]
        case .walking:
            return [.walking, .strength]
        }
    }
}

struct TrainingPlanCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    @State private var creationMode: TrainingPlanCreationMode?

    @State private var title = "My Program"
    @State private var summary = ""
    @State private var simpleFocus: SimpleTrainingPlanFocus = .hybrid
    @State private var simpleSessionsPerWeek = 4
    @State private var simpleWeekCount = 8

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
                calendar.dateComponents(
                    [.day],
                    from: start,
                    to: end
                ).day ?? 0,
                0
            )
            return min(
                max(Int(ceil(Double(days + 1) / 7.0)), 1),
                52
            )
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
            Group {
                if creationMode == nil {
                    creationModeChoice
                } else if creationMode == .simple {
                    simpleForm
                } else {
                    advancedForm
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(creationMode == nil ? "Cancel" : "Back") {
                        if creationMode == nil {
                            dismiss()
                        } else {
                            creationMode = nil
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if let creationMode {
                        Button("Create") {
                            createPlan(mode: creationMode)
                        }
                        .disabled(
                            title
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                        )
                    }
                }
            }
        }
    }

    private var navigationTitle: String {
        switch creationMode {
        case .simple:
            return "Simple Plan"
        case .advanced:
            return "Advanced Plan"
        case nil:
            return "New Training Plan"
        }
    }

    private var creationModeChoice: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How do you want to build it?")
                        .font(.title2.weight(.bold))

                    Text(
                        "You can always edit the plan in detail afterwards. This only changes how much ATHLTH sets up for you now."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                creationModeButton(.simple)
                creationModeButton(.advanced)
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.55)
            )
        )
    }

    private func creationModeButton(
        _ mode: TrainingPlanCreationMode
    ) -> some View {
        Button {
            creationMode = mode
        } label: {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.accent)
                    .frame(width: 50, height: 50)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 15)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(mode.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        if mode == .advanced {
                            Text("FULL CONTROL")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(ATHLTHTheme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: Capsule()
                                )
                        }
                    }

                    Text(mode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    Text(
                        mode == .simple
                            ? "Best for getting started quickly"
                            : "Best for structured multi-week programming"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                    .padding(.top, 3)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }
            .padding(18)
            .background(
                Color.white.opacity(0.88),
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(Color.black.opacity(0.045), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var simpleForm: some View {
        Form {
            Section("Plan") {
                TextField("Plan name", text: $title)

                DatePicker(
                    "Start date",
                    selection: $startDate,
                    displayedComponents: .date
                )
            }

            Section("Training Focus") {
                Picker("Focus", selection: $simpleFocus) {
                    ForEach(SimpleTrainingPlanFocus.allCases) { focus in
                        Label(
                            focus.title,
                            systemImage: focus.icon
                        )
                        .tag(focus)
                    }
                }

                Text(simpleFocus.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Weekly Rhythm") {
                Stepper(
                    "\(simpleSessionsPerWeek) sessions per week",
                    value: $simpleSessionsPerWeek,
                    in: 2...6
                )

                HStack(spacing: 7) {
                    ForEach(
                        Array(simplePreviewKinds.enumerated()),
                        id: \.offset
                    ) { index, kind in
                        VStack(spacing: 5) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 15, weight: .semibold))
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(ATHLTHTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            ATHLTHTheme.accentSoft,
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                    }
                }

                Text(
                    "ATHLTH spreads these sessions across the week. You can move, replace or fully rebuild them later."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Length") {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 76),
                            spacing: 8
                        )
                    ],
                    spacing: 8
                ) {
                    ForEach([4, 8, 12, 16, 24], id: \.self) { weeks in
                        Button {
                            simpleWeekCount = weeks
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(weeks)")
                                    .font(.headline)
                                Text("weeks")
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(
                                simpleWeekCount == weeks
                                    ? Color.white
                                    : ATHLTHTheme.primaryText
                            )
                            .background(
                                simpleWeekCount == weeks
                                    ? ATHLTHTheme.accent
                                    : Color(
                                        .tertiarySystemGroupedBackground
                                    ),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Text(
                    "Simple creates a complete starting rhythm, not a locked template. Open Plan afterwards to add exercises, structured runs, routes, target distance, time and notes."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedForm: some View {
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
                            GridItem(
                                .adaptive(minimum: 78),
                                spacing: 8
                            )
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
                                    Text(
                                        weeks == 1
                                            ? "week"
                                            : "weeks"
                                    )
                                    .font(.caption2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .foregroundStyle(
                                    !useCustomWeeks &&
                                    weekCount == weeks
                                        ? Color.white
                                        : ATHLTHTheme.primaryText
                                )
                                .background(
                                    !useCustomWeeks &&
                                    weekCount == weeks
                                        ? ATHLTHTheme.accent
                                        : Color(
                                            .tertiarySystemGroupedBackground
                                        ),
                                    in: RoundedRectangle(
                                        cornerRadius: 12
                                    )
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
                    value:
                        "\(resolvedWeeks) " +
                        (resolvedWeeks == 1 ? "week" : "weeks")
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
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(goal.title)
                                Text(goal.category.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("What Advanced Unlocks") {
                Label(
                    "Exact workout on any day",
                    systemImage: "calendar.badge.plus"
                )
                Label(
                    "Strength exercises, sets, reps, load, RPE / RIR and progression",
                    systemImage: "dumbbell.fill"
                )
                Label(
                    "Structured running blocks, distance and routes",
                    systemImage: "figure.run"
                )
                Label(
                    "Mobility, recovery, notes and scheduled time",
                    systemImage: "clock"
                )

                Text(
                    "The new plan starts with an empty calendar so you decide exactly what belongs on each day."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var simplePreviewKinds: [WorkoutKind] {
        let pattern = simpleFocus.pattern

        guard !pattern.isEmpty else {
            return []
        }

        return (0..<simpleSessionsPerWeek).map {
            pattern[$0 % pattern.count]
        }
    }

    private func createPlan(
        mode: TrainingPlanCreationMode
    ) {
        switch mode {
        case .simple:
            let autoSummary =
                "\(simpleFocus.title) · " +
                "\(simpleSessionsPerWeek) sessions per week"

            session.createSimpleTrainingPlan(
                title: title,
                summary: autoSummary,
                weekCount: simpleWeekCount,
                startDate: startDate,
                visibility: .privateOnly,
                sessionsPerWeek: simpleSessionsPerWeek,
                workoutPattern: simpleFocus.pattern
            )

        case .advanced:
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
        }

        dismiss()
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
    @State private var weekCount: Int
    @State private var selectedGoalIDs: Set<UUID> = []

    init(plan: TrainingPlan) {
        self.plan = plan
        _title = State(initialValue: plan.title)
        _summary = State(initialValue: plan.summary)
        _visibility = State(initialValue: plan.visibility)
        _tags = State(initialValue: plan.tags.joined(separator: ", "))
        _startDateEnabled = State(initialValue: plan.startDate != nil)
        _startDate = State(initialValue: plan.startDate ?? Date())
        _weekCount = State(initialValue: max(plan.weeks.count, 1))
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

                    TextField(
                        "Tags, comma separated",
                        text: $tags
                    )
                    .textInputAutocapitalization(.never)
                }

                Section("Timeline") {
                    Stepper(
                        "\(weekCount) \(weekCount == 1 ? "week" : "weeks")",
                        value: $weekCount,
                        in: 1...52
                    )

                    Toggle("Use calendar start date", isOn: $startDateEnabled)

                    if startDateEnabled {
                        DatePicker(
                            "Program starts",
                            selection: $startDate,
                            displayedComponents: .date
                        )

                        if let endDate = Calendar.current.date(
                            byAdding: .day,
                            value: max(weekCount * 7 - 1, 0),
                            to: Calendar.current.startOfDay(for: startDate)
                        ) {
                            LabeledContent(
                                "Program ends",
                                value: endDate.formatted(
                                    date: .abbreviated,
                                    time: .omitted
                                )
                            )
                        }
                    }
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
                        session.setActivePlanWeekCount(weekCount)
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

                    Stepper(
                        "Duration: \(durationMinutes) min",
                        value: $durationMinutes,
                        in: 5...300,
                        step: 5
                    )

                    if kind == .walking || kind == .running {
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
                VStack(alignment: .leading, spacing: 5) {
                    Text("Freestyle strength workout")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        "You can add this workout now and choose exercises later, or add exercises below for a structured session."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "figure.run")
                                .foregroundStyle(ATHLTHTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open run")
                                    .font(.subheadline.weight(.semibold))
                                Text("Use the duration and distance above, or choose a structured workout.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            showingRunningLibrary = true
                        } label: {
                            Label(
                                "Choose Structured Running Workout",
                                systemImage: "list.bullet.rectangle"
                            )
                        }
                    }
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
                NavigationLink {
                    RunRouteBuilderView()
                } label: {
                    Label("Create a Route", systemImage: "map.fill")
                }

                Text(
                    "Routes are optional. Create one in ATHLTH and it will appear here."
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
            durationMinutes: durationMinutes,
            targetDistanceKilometers:
                selectedRunningWorkout?
                    .estimatedDistanceMeters
                    .map { $0 / 1_000 }
                ?? ((kind == .walking || kind == .running)
                    ? distanceKilometers
                    : nil),
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
