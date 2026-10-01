import SwiftUI

struct AdvancedPlannerView: View {
    @EnvironmentObject private var session: AppSessionStore

    let planID: UUID?
    let showsEmptyState: Bool

    @State private var selectedWeekID: UUID?
    @State private var selectedDayID: UUID?
    @State private var selectedWorkout: PlannedSession?
    @State private var showingSessionEditor = false
    @State private var showingPlanEditor = false
    @State private var showingAllPlans = false
    @State private var showingProgramCreation = false
    @State private var weekPendingRemoval: TrainingPlanWeek?

    init(
        planID: UUID? = nil,
        showsEmptyState: Bool = true
    ) {
        self.planID = planID
        self.showsEmptyState = showsEmptyState
    }

    private var displayedPlan: TrainingPlan? {
        if let planID {
            return session.trainingPlan(withID: planID)
        }

        return session.activePlan
    }

    var body: some View {
        VStack(spacing: 16) {
            if let plan = displayedPlan {
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
            } else if showsEmptyState {
                emptyPlanState
            }
        }
        .onAppear {
            session.refreshActivePlanForToday()
            syncSelection()
        }
        .onChange(of: displayedPlan?.id) { _, _ in
            syncSelection()
        }
        .onChange(of: displayedPlan?.version) { _, _ in
            reconcileSelection()
        }
        .sheet(isPresented: $showingSessionEditor) {
            if let selectedDayID,
               let plan = displayedPlan {
                SessionEditorView(
                    planID: plan.id,
                    dayID: selectedDayID
                )
            }
        }
        .sheet(isPresented: $showingPlanEditor) {
            if let plan = displayedPlan {
                PlanMetadataEditorView(plan: plan)
            }
        }
        .sheet(isPresented: $showingAllPlans) {
            AllTrainingPlansView()
        }
        .sheet(isPresented: $showingProgramCreation) {
            TrainingPlanCreationView()
        }
        .sheet(item: $selectedWorkout) { workout in
            if let planID = displayedPlan?.id {
                PlannedWorkoutDetailView(
                    planID: planID,
                    workout: workout,
                    isHealthCompleted: false
                )
                .environmentObject(session)
            }
        }
        .confirmationDialog(
            weekPendingRemoval.map {
                "Remove W\($0.weekNumber)?"
            } ?? "Remove week?",
            isPresented: Binding(
                get: { weekPendingRemoval != nil },
                set: { presented in
                    if !presented {
                        weekPendingRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let week = weekPendingRemoval {
                Button(
                    "Remove W\(week.weekNumber)",
                    role: .destructive
                ) {
                    if let plan = displayedPlan {
                        removeWeek(week, from: plan)
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                weekPendingRemoval = nil
            }
        } message: {
            if let week = weekPendingRemoval {
                let count = week.days.reduce(0) {
                    $0 + $1.sessions.count
                }

                Text(
                    count == 1
                        ? "This week contains 1 planned workout. Removing the week will also remove that workout."
                        : "This week contains \(count) planned workouts. Removing the week will also remove those workouts."
                )
            }
        }
    }

    private func planOverview(_ plan: TrainingPlan) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 14) {
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

                    HStack(spacing: 8) {
                        if planID == nil {
                            Button {
                                showingAllPlans = true
                            } label: {
                                Image(systemName: "square.stack.3d.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel("All training plans")
                        }

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
            }
        }
    }

    private func weekSelector(_ plan: TrainingPlan) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weeks")
                            .font(.title3.weight(.bold))
                        Text("Jump between weeks without leaving the planner.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            session.addWeekToTrainingPlan(
                                planID: plan.id
                            )
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(plan.weeks.count >= 52)

                        Menu {
                            if let week = selectedWeek(in: plan) {
                                Button(role: .destructive) {
                                    requestWeekRemoval(
                                        week,
                                        from: plan
                                    )
                                } label: {
                                    Label(
                                        "Remove W\(week.weekNumber)",
                                        systemImage: "trash"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(
                                    .system(
                                        size: 15,
                                        weight: .semibold
                                    )
                                )
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .controlSize(.small)
                        .disabled(plan.weeks.count <= 1)
                        .accessibilityLabel("Week actions")
                    }
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
                                selectBestDay(
                                    in: week,
                                    plan: plan
                                )
                            } label: {
                                VStack(spacing: 3) {
                                    Text("W\(week.weekNumber)")
                                        .font(.subheadline.weight(.bold))

                                    Text(
                                        count == 1
                                            ? "1 session"
                                            : "\(count) sessions"
                                    )
                                    .font(
                                        .system(
                                            size: 9,
                                            weight: .semibold
                                        )
                                    )
                                    .opacity(0.78)
                                }
                                .foregroundStyle(
                                    selected
                                        ? Color.white
                                        : ATHLTHTheme.primaryText
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
            }
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
            VStack(alignment: .leading, spacing: 12) {
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

                        Text(
                            daySubtitle(
                                day,
                                week: week,
                                plan: plan
                            )
                        )
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
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

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
                } else {
                    VStack(spacing: 10) {
                        ForEach(day.sessions) { workout in
                            sessionRow(
                                workout,
                                dayID: day.id
                            )
                        }
                    }
                }
            }
        }
    }

    private func weekOverview(
        _ plan: TrainingPlan,
        week: TrainingPlanWeek
    ) -> some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 8) {
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
                        ATHLTHLocalization.format(
                                english: "%d total",
                                norwegian: "%d totalt",
                                week.days.reduce(0) { $0 + $1.sessions.count }
                            )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accent)
                }

                VStack(spacing: 0) {
                    ForEach(
                        Array(week.days.enumerated()),
                        id: \.element.id
                    ) { index, day in
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
                                .frame(
                                    width: 34,
                                    alignment: .leading
                                )

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        day.sessions.isEmpty
                                            ? "Rest"
                                            : day.sessions
                                                .map(\.title)
                                                .joined(
                                                    separator: " · "
                                                )
                                    )
                                    .font(
                                        .subheadline.weight(.semibold)
                                    )
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )
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
                                        .foregroundStyle(
                                            ATHLTHTheme.accent
                                        )
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
            }
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
                        showingAllPlans = true
                    } label: {
                        Label("All Plans", systemImage: "square.stack.3d.up")
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
        let planID = displayedPlan?.id
        let completed =
            planID.map {
                session.isPlanSessionManuallyCompleted(
                    planID: $0,
                    sessionID: workout.id
                )
            } ?? false

        return HStack(spacing: 8) {
            Button {
                selectedWorkout = workout
            } label: {
                HStack(spacing: 11) {
                    Image(
                        systemName: completed
                            ? "checkmark.circle.fill"
                            : workout.kind.systemImage
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        completed
                            ? ATHLTHTheme.vitality
                            : ATHLTHTheme.accent
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        (
                            completed
                                ? ATHLTHTheme.vitalitySoft
                                : ATHLTHTheme.accentSoft
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(workout.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    completed
                                        ? ATHLTHTheme.mutedText
                                        : ATHLTHTheme.primaryText
                                )

                            if completed {
                                Text("Completed")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(ATHLTHTheme.vitality)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        ATHLTHTheme.vitalitySoft,
                                        in: Capsule()
                                    )
                            } else if let start = workout.scheduledStart {
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
                            .foregroundStyle(
                                completed
                                    ? ATHLTHTheme.mutedText.opacity(0.72)
                                    : Color.secondary
                            )
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(11)
                .background(
                    completed
                        ? ATHLTHTheme.vitalitySoft.opacity(0.28)
                        : Color.primary.opacity(0.025),
                    in: RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)

            Menu {
                if let planID,
                   let plan = displayedPlan,
                   session.trainingPlanStatus(plan) == .active {
                    Button {
                        session.setPlanSessionManuallyCompleted(
                            planID: planID,
                            sessionID: workout.id,
                            completed: !completed
                        )
                    } label: {
                        Label(
                            completed
                                ? "Mark as Not Completed"
                                : "Mark as Completed",
                            systemImage: completed
                                ? "arrow.uturn.backward.circle"
                                : "checkmark.circle"
                        )
                    }

                    Divider()
                }

                Button(role: .destructive) {
                    if let planID = displayedPlan?.id {
                        session.removeSession(
                            workout.id,
                            fromDay: dayID,
                            inPlan: planID
                        )
                    }
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

    private func requestWeekRemoval(
        _ week: TrainingPlanWeek,
        from plan: TrainingPlan
    ) {
        let sessionCount = week.days.reduce(0) {
            $0 + $1.sessions.count
        }

        if sessionCount == 0 {
            removeWeek(week, from: plan)
        } else {
            weekPendingRemoval = week
        }
    }

    private func removeWeek(
        _ week: TrainingPlanWeek,
        from plan: TrainingPlan
    ) {
        guard plan.weeks.count > 1,
              let removedIndex = plan.weeks.firstIndex(
                where: { $0.id == week.id }
              )
        else {
            return
        }

        session.removeWeekFromTrainingPlan(
            planID: plan.id,
            weekID: week.id
        )

        guard let updatedPlan =
                session.trainingPlan(withID: plan.id),
              !updatedPlan.weeks.isEmpty
        else {
            syncSelection()
            return
        }

        let targetIndex = min(
            removedIndex,
            updatedPlan.weeks.count - 1
        )
        let targetWeek = updatedPlan.weeks[targetIndex]

        selectedWeekID = targetWeek.id
        selectBestDay(
            in: targetWeek,
            plan: updatedPlan
        )
        weekPendingRemoval = nil
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
        guard let plan = displayedPlan,
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
        guard let plan = displayedPlan else {
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

        let runningWorkouts = workout.resolvedRunningWorkouts

        if !runningWorkouts.isEmpty {
            parts.append(
                runningWorkouts.count == 1
                    ? runningWorkouts[0].type.title
                    : "\(runningWorkouts.count) run workouts"
            )

            if let duration = workout.durationMinutes {
                parts.append("\(duration) min")
            }

            if let distance = workout.targetDistanceKilometers {
                parts.append(
                    String(format: "%.1f km", distance)
                )
            }
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

struct AllTrainingPlansView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    @State private var showingCreatePlan = false
    @State private var editingPlan: TrainingPlan?
    @State private var planToOpen: TrainingPlan?
    @State private var planPendingDeletion: TrainingPlan?

    private var activePlans: [TrainingPlan] {
        session.trainingPlans.filter {
            session.trainingPlanStatus($0) == .active
        }
    }

    private var upcomingPlans: [TrainingPlan] {
        session.trainingPlans
            .filter {
                session.trainingPlanStatus($0) == .upcoming
            }
            .sorted {
                ($0.startDate ?? .distantFuture) <
                ($1.startDate ?? .distantFuture)
            }
    }

    private var completedPlans: [TrainingPlan] {
        session.trainingPlans
            .filter {
                session.trainingPlanStatus($0) == .completed
            }
            .sorted {
                (session.trainingPlanEndDate($0) ?? .distantPast) >
                (session.trainingPlanEndDate($1) ?? .distantPast)
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if session.trainingPlans.isEmpty {
                        ContentUnavailableView {
                            Label(
                                "No training plans yet",
                                systemImage: "calendar.badge.plus"
                            )
                        } description: {
                            Text(
                                "Create your first dated plan. ATHLTH keeps only the plan covering today active."
                            )
                        } actions: {
                            Button("Create Plan") {
                                showingCreatePlan = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ATHLTHTheme.accent)
                        }
                        .padding(.top, 36)
                    } else {
                        planSection(
                            "Active",
                            plans: activePlans,
                            status: .active
                        )
                        planSection(
                            "Upcoming",
                            plans: upcomingPlans,
                            status: .upcoming
                        )
                        planSection(
                            "Completed",
                            plans: completedPlans,
                            status: .completed
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent: ATHLTHTheme.accent.opacity(0.45)
                )
            )
            .navigationTitle("All Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreatePlan = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create training plan")
                }
            }
            .sheet(isPresented: $showingCreatePlan) {
                TrainingPlanCreationView()
            }
            .sheet(item: $editingPlan) { plan in
                PlanMetadataEditorView(plan: plan)
            }
            .sheet(item: $planToOpen) { plan in
                NavigationStack {
                    ScrollView {
                        AdvancedPlannerView(
                            planID: plan.id
                        )
                        .padding()
                    }
                    .background(
                        ATHLTHPremiumCanvas(
                            accent: ATHLTHTheme.accent.opacity(0.45)
                        )
                    )
                    .navigationTitle(plan.title)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .confirmationDialog(
                planPendingDeletion.map {
                    "Delete \($0.title)?"
                } ?? "Delete training plan?",
                isPresented: Binding(
                    get: { planPendingDeletion != nil },
                    set: { presented in
                        if !presented {
                            planPendingDeletion = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let plan = planPendingDeletion {
                    Button("Delete Plan", role: .destructive) {
                        goalStore.setLinkedPlan(
                            plan.id,
                            goalIDs: []
                        )
                        session.deleteTrainingPlan(plan.id)
                        planPendingDeletion = nil
                    }
                }

                Button("Cancel", role: .cancel) {
                    planPendingDeletion = nil
                }
            } message: {
                Text(
                    "This removes the plan and its future schedule. Completed workout history is kept."
                )
            }
            .onAppear {
                session.refreshActivePlanForToday()
            }
        }
    }

    @ViewBuilder
    private func planSection(
        _ title: String,
        plans: [TrainingPlan],
        status: TrainingPlanTimingStatus
    ) -> some View {
        if !plans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(ATHLTHTheme.primaryText)

                ForEach(plans) { plan in
                    planCard(plan, status: status)
                }
            }
        }
    }

    private func planCard(
        _ plan: TrainingPlan,
        status: TrainingPlanTimingStatus
    ) -> some View {
        ATHLTHCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon(status))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(statusTint(status))
                    .frame(width: 42, height: 42)
                    .background(
                        statusTint(status).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 13)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(plan.title)
                            .font(.headline)
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)

                        Text(statusTitle(status))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(statusTint(status))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                statusTint(status).opacity(0.10),
                                in: Capsule()
                            )
                    }

                    Text(planDateText(plan))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(
                        plan.weeks.count == 1
                            ? "1 week"
                            : "\(plan.weeks.count) weeks"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    if !plan.summary
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty {
                        Text(plan.summary)
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme.primaryText.opacity(0.72)
                            )
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 6)

                Menu {
                    Button {
                        editingPlan = plan
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                    }

                    Button {
                        _ = session.duplicateTrainingPlan(plan.id)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        planPendingDeletion = plan
                    } label: {
                        Label("Delete Plan", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }

            Button {
                if status == .active {
                    dismiss()
                } else {
                    planToOpen = plan
                }
            } label: {
                Label(
                    status == .active
                        ? "Open Current Plan"
                        : "Open Plan",
                    systemImage: "arrow.right"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(ATHLTHTheme.accent)
            .padding(.top, 10)
        }
    }

    private func planDateText(
        _ plan: TrainingPlan
    ) -> String {
        guard let startDate = plan.startDate else {
            return "No dates"
        }

        let start = startDate.formatted(
            date: .abbreviated,
            time: .omitted
        )

        guard let endDate = session.trainingPlanEndDate(plan) else {
            return start
        }

        return "\(start) – " +
            endDate.formatted(
                date: .abbreviated,
                time: .omitted
            )
    }

    private func statusTitle(
        _ status: TrainingPlanTimingStatus
    ) -> String {
        switch status {
        case .active: return "ACTIVE"
        case .upcoming: return "UPCOMING"
        case .completed: return "COMPLETED"
        case .unscheduled: return "UNSCHEDULED"
        }
    }

    private func statusIcon(
        _ status: TrainingPlanTimingStatus
    ) -> String {
        switch status {
        case .active: return "play.circle.fill"
        case .upcoming: return "calendar.badge.clock"
        case .completed: return "checkmark.circle.fill"
        case .unscheduled: return "calendar"
        }
    }

    private func statusTint(
        _ status: TrainingPlanTimingStatus
    ) -> Color {
        switch status {
        case .active: return ATHLTHTheme.vitality
        case .upcoming: return ATHLTHTheme.accent
        case .completed: return ATHLTHTheme.mutedText
        case .unscheduled: return .orange
        }
    }
}


struct TrainingPlanManagerView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    let onOpenCalendar: () -> Void

    @State private var showingProgramCreation = false
    @State private var showingAllPlans = false
    @State private var programToStart: TrainingPlan?
    @State private var aiMode: AIProgramGenerationMode?
    @State private var showingPlanAdaptation = false
    @State private var showingAISubscriptionOffer = false

    init(onOpenCalendar: @escaping () -> Void = {}) {
        self.onOpenCalendar = onOpenCalendar
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("YOUR TRAINING PLAN")
                        .font(.caption2.weight(.bold))
                        .tracking(2.4)
                        .foregroundStyle(ATHLTHTheme.mutedText)

                    Text(
                        session.activePlan == nil
                            ? "Build what comes next."
                            : "Keep building."
                    )
                    .font(
                        .system(
                            size: 30,
                            weight: .bold,
                            design: .serif
                        )
                    )

                    Text(
                        session.activePlan == nil
                            ? "Create it yourself or let ATHLTH Coach shape a draft around your goals and everyday life."
                            : "Your active plan stays in focus. Create another plan or ask Coach to help when life changes."
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }

                HStack(spacing: 10) {
                    Button {
                        showingProgramCreation = true
                    } label: {
                        Label("Create plan", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .background(
                                Color.white.opacity(0.84),
                                in: RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        openAI(.generate)
                    } label: {
                        Label("ATHLTH Coach", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(.white)
                            .background(
                                ATHLTHTheme.accentDeep,
                                in: RoundedRectangle(
                                    cornerRadius: 16,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 18) {
                    Button {
                        showingAllPlans = true
                    } label: {
                        Label(
                            "All plans",
                            systemImage: "square.stack.3d.up"
                        )
                    }

                    if session.activePlan != nil {
                        Button {
                            openPlanAdaptation()
                        } label: {
                            Label(
                                "Adapt plan",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }

                        Button {
                            openAI(.complete)
                        } label: {
                            Label(
                                "Fill empty days",
                                systemImage: "wand.and.stars"
                            )
                        }
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
            }
            .padding(2)

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

        }
        .sheet(isPresented: $showingAllPlans) {
            AllTrainingPlansView()
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
        .sheet(isPresented: $showingPlanAdaptation) {
            CoachPlanAdaptationView()
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

    @ViewBuilder
    private var creationButtons: some View {
        Button {
            showingProgramCreation = true
        } label: {
            Label("Create a plan", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        Button {
            openAI(.generate)
        } label: {
            Label("ATHLTH Coach", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(ATHLTHTheme.accent)
    }

    private func openPlanAdaptation() {
        guard session.canAccess(.aiTrainingPrograms) else {
            showingAISubscriptionOffer = true
            return
        }

        showingPlanAdaptation = true
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

    @State private var startDate =
        Calendar.current.startOfDay(for: Date())

    private var endDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(program.weeks.count * 7 - 1, 0),
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private var conflictingPlan: TrainingPlan? {
        session.trainingPlanConflict(
            startDate: startDate,
            endDate: endDate
        )
    }

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

                    LabeledContent(
                        "Length",
                        value: "\(program.weeks.count) weeks"
                    )
                }

                Section("Add to Calendar") {
                    DatePicker(
                        "Start date",
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    LabeledContent(
                        "Ends",
                        value: endDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )

                    Text(
                        "ATHLTH adds this program to your plan timeline. It becomes active automatically when today falls inside this date range."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let conflict = conflictingPlan {
                    Section("Schedule Conflict") {
                        Label(
                            ATHLTHLocalization.format(
                                english: "Overlaps with %@",
                                norwegian: "Overlapper med %@",
                                conflict.title
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)

                        Text(
                            "Choose a start date after the existing plan ends. Only one training plan can be active on a given date."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
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
                        guard let created =
                                session.usePlanTemplate(
                                    program.id,
                                    startDate: startDate
                                )
                        else {
                            return
                        }

                        dismiss()

                        if session.trainingPlanStatus(created) == .active {
                            onStarted()
                        }
                    }
                    .disabled(conflictingPlan != nil)
                }
            }
            .onAppear {
                startDate = session.suggestedTrainingPlanStartDate
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
        case .simple: return "Quick Start"
        case .advanced: return "Build from Scratch"
        }
    }

    var subtitle: String {
        switch self {
        case .simple:
            return "Create a lightweight starter rhythm."
        case .advanced:
            return "Start with a blank calendar and shape every week yourself."
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

struct SimpleTrainingPlanCreationView: View {
    var body: some View {
        TrainingPlanCreationView(initialMode: .simple)
    }
}

struct AdvancedTrainingPlanCreationView: View {
    var body: some View {
        TrainingPlanCreationView(initialMode: .advanced)
    }
}

struct TrainingPlanCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore

    @State private var creationMode: TrainingPlanCreationMode?

    init() {
        _creationMode = State(initialValue: nil)
    }

    fileprivate init(
        initialMode: TrainingPlanCreationMode
    ) {
        _creationMode = State(initialValue: initialMode)
    }

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
    @State private var creationError: String?

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

    private var simpleEndDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(simpleWeekCount * 7 - 1, 0),
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private var proposedEndDate: Date {
        creationMode == .simple
            ? simpleEndDate
            : resolvedEndDate
    }

    private var conflictingPlan: TrainingPlan? {
        guard creationMode != nil else {
            return nil
        }

        return session.trainingPlanConflict(
            startDate: startDate,
            endDate: proposedEndDate
        )
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
            }
        }
        .alert(
            "Plan Conflict",
            isPresented: Binding(
                get: { creationError != nil },
                set: { shown in
                    if !shown {
                        creationError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(creationError ?? "")
        }
    }

    private var navigationTitle: String {
        switch creationMode {
        case .simple:
            return "Quick Start"
        case .advanced:
            return "Build from Scratch"
        case nil:
            return "New Training Plan"
        }
    }

    private var creationModeChoice: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("CREATE A TRAINING PLAN")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.0)
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text("Start your way")
                        .font(
                            .system(
                                size: 34,
                                weight: .semibold,
                                design: .serif
                            )
                        )
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        "There are only two useful starting points: build a blank plan yourself, or choose a complete plan from the Library. Both stay fully editable afterwards."
                    )
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineSpacing(2)
                }
                .padding(.bottom, 2)

                Button {
                    beginScratchCreation()
                } label: {
                    creationPathCard(
                        eyebrow: "BLANK PLAN",
                        title: "Build from scratch",
                        subtitle:
                            "Choose the dates and goals, then add every workout exactly where you want it.",
                        badge: "FULL CONTROL",
                        icon: "calendar.badge.plus",
                        accent: ATHLTHTheme.accentDeep,
                        prominent: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TrainingPlanLibraryView()
                } label: {
                    creationPathCard(
                        eyebrow: "TRAINING LIBRARY",
                        title: "Choose a training plan",
                        subtitle:
                            "Browse curated running, strength and hybrid plans, preview every week and make one yours.",
                        badge: "READY TO USE",
                        icon: "square.stack.3d.up.fill",
                        accent: ATHLTHTheme.premiumGold,
                        prominent: false
                    )
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accent)

                    Text(
                        "Nothing is locked. After creation you can move days, replace workouts, edit exercises, routes, targets and times."
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.38)
            )
        )
    }

    private func creationPathCard(
        eyebrow: String,
        title: String,
        subtitle: String,
        badge: String,
        icon: String,
        accent: Color,
        prominent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(
                        prominent ? Color.white : accent
                    )
                    .frame(width: 56, height: 56)
                    .background(
                        prominent
                            ? Color.white.opacity(0.14)
                            : accent.opacity(0.11),
                        in: RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 17,
                            style: .continuous
                        )
                        .stroke(
                            prominent
                                ? Color.white.opacity(0.20)
                                : Color.white.opacity(0.92),
                            lineWidth: 0.8
                        )
                    }

                Spacer()

                Text(badge)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(
                        prominent
                            ? Color.white.opacity(0.86)
                            : accent
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        prominent
                            ? Color.white.opacity(0.12)
                            : accent.opacity(0.09),
                        in: Capsule()
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(
                        prominent
                            ? Color.white.opacity(0.68)
                            : accent.opacity(0.85)
                    )

                Text(title)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(
                        prominent
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(
                        prominent
                            ? Color.white.opacity(0.76)
                            : ATHLTHTheme.mutedText
                    )
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
            }

            HStack {
                Text(
                    prominent
                        ? "Empty calendar · your structure"
                        : "Preview first · personalise after"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    prominent
                        ? Color.white.opacity(0.78)
                        : ATHLTHTheme.primaryText.opacity(0.68)
                )

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        prominent
                            ? Color.white
                            : accent
                    )
                    .frame(width: 34, height: 34)
                    .background(
                        prominent
                            ? Color.white.opacity(0.14)
                            : accent.opacity(0.09),
                        in: Circle()
                    )
            }
        }
        .padding(20)
        .background(
            Group {
                if prominent {
                    LinearGradient(
                        colors: [
                            ATHLTHTheme.accentDeep,
                            ATHLTHTheme.accentDeep.opacity(0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            accent.opacity(0.055)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            },
            in: RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                prominent
                    ? Color.white.opacity(0.12)
                    : Color.white.opacity(0.96),
                lineWidth: 1
            )
        }
        .shadow(
            color: prominent
                ? ATHLTHTheme.accentDeep.opacity(0.20)
                : Color.black.opacity(0.055),
            radius: prominent ? 20 : 14,
            x: 0,
            y: prominent ? 10 : 7
        )
    }

    private func beginScratchCreation() {
        creationMode = .advanced

        let suggested = session.suggestedTrainingPlanStartDate
        startDate = suggested
        endDate = Calendar.current.date(
            byAdding: .day,
            value: 27,
            to: suggested
        ) ?? suggested
    }

    private var simpleForm: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                builderIntro(
                    eyebrow: "QUICK START",
                    title: "Set the rhythm",
                    subtitle:
                        "ATHLTH creates a lightweight starting schedule. You can still rebuild every workout afterwards.",
                    icon: "wand.and.stars",
                    accent: ATHLTHTheme.vitality
                )

                creationPanel(
                    eyebrow: "01 · BASICS",
                    title: "Plan & focus",
                    subtitle: "Name the plan and choose the training bias.",
                    icon: "scope",
                    accent: ATHLTHTheme.vitality
                ) {
                    VStack(spacing: 12) {
                        premiumTextField(
                            "Plan name",
                            text: $title
                        )

                        DatePicker(
                            "Start date",
                            selection: $startDate,
                            displayedComponents: .date
                        )
                        .font(.subheadline.weight(.semibold))

                        Divider()

                        Picker("Training focus", selection: $simpleFocus) {
                            ForEach(SimpleTrainingPlanFocus.allCases) { focus in
                                Label(
                                    focus.title,
                                    systemImage: focus.icon
                                )
                                .tag(focus)
                            }
                        }

                        HStack(spacing: 9) {
                            Image(systemName: simpleFocus.icon)
                                .foregroundStyle(ATHLTHTheme.vitality)

                            Text(simpleFocus.subtitle)
                                .font(.caption)
                                .foregroundStyle(ATHLTHTheme.mutedText)

                            Spacer()
                        }
                    }
                }

                creationPanel(
                    eyebrow: "02 · WEEKLY RHYTHM",
                    title: "\(simpleSessionsPerWeek) sessions per week",
                    subtitle:
                        "ATHLTH spreads the sessions across the week. You can move them at any time.",
                    icon: "calendar.day.timeline.left",
                    accent: ATHLTHTheme.accent
                ) {
                    VStack(spacing: 13) {
                        Stepper(
                            "\(simpleSessionsPerWeek) sessions",
                            value: $simpleSessionsPerWeek,
                            in: 2...6
                        )

                        HStack(spacing: 7) {
                            ForEach(
                                Array(simplePreviewKinds.enumerated()),
                                id: \.offset
                            ) { index, kind in
                                VStack(spacing: 6) {
                                    Image(systemName: kind.systemImage)
                                        .font(.system(size: 16, weight: .semibold))

                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(ATHLTHTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            ATHLTHTheme.accentSoft,
                                            Color.white.opacity(0.72)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    in: RoundedRectangle(
                                        cornerRadius: 13,
                                        style: .continuous
                                    )
                                )
                            }
                        }
                    }
                }

                creationPanel(
                    eyebrow: "03 · LENGTH",
                    title: "How long is the plan?",
                    subtitle: "Pick a duration. You can extend or shorten it later.",
                    icon: "calendar.badge.clock",
                    accent: ATHLTHTheme.premiumGold
                ) {
                    durationChipGrid(
                        options: [4, 8, 12, 16, 24],
                        selected: simpleWeekCount
                    ) { weeks in
                        simpleWeekCount = weeks
                    }
                }

                if let conflict = conflictingPlan {
                    planConflictCard(
                        conflict,
                        message:
                            "Choose a start date after the existing plan ends. ATHLTH keeps one active plan on each date."
                    )
                }

                createPlanButton(
                    mode: .simple,
                    title: "Create Quick Plan",
                    subtitle: "\(simpleWeekCount) weeks · \(simpleSessionsPerWeek) sessions / week"
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.vitality.opacity(0.20)
            )
        )
    }

    private var advancedForm: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                builderIntro(
                    eyebrow: "BUILD FROM SCRATCH",
                    title: "Your plan. Your structure.",
                    subtitle:
                        "Create the calendar first. The plan opens empty, ready for strength sessions, running workouts, routes, targets and recovery days.",
                    icon: "calendar.badge.plus",
                    accent: ATHLTHTheme.accent
                )

                creationPanel(
                    eyebrow: "01 · IDENTITY",
                    title: "Name the plan",
                    subtitle: "Keep it clear enough to recognise later in My Plans.",
                    icon: "pencil.line",
                    accent: ATHLTHTheme.accent
                ) {
                    VStack(spacing: 12) {
                        premiumTextField(
                            "Program name",
                            text: $title
                        )

                        premiumTextField(
                            "What are you training for?",
                            text: $summary,
                            axis: .vertical
                        )
                        .lineLimit(2...5)

                        Divider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Visibility")
                                    .font(.subheadline.weight(.semibold))

                                Text("Who can see this plan")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHTheme.mutedText)
                            }

                            Spacer()

                            Picker("Visibility", selection: $visibility) {
                                ForEach(ProfileVisibility.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                }

                creationPanel(
                    eyebrow: "02 · TIMELINE",
                    title: "Define the plan window",
                    subtitle: "Choose a start date and either a fixed number of weeks or an end date.",
                    icon: "calendar",
                    accent: ATHLTHTheme.premiumGold
                ) {
                    VStack(spacing: 13) {
                        DatePicker(
                            "Start date",
                            selection: $startDate,
                            displayedComponents: .date
                        )
                        .font(.subheadline.weight(.semibold))

                        Picker("Plan by", selection: $timelineMode) {
                            ForEach(ProgramTimelineMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if timelineMode == .weeks {
                            durationChipGrid(
                                options: quickDurations,
                                selected:
                                    useCustomWeeks
                                        ? nil
                                        : weekCount
                            ) { weeks in
                                weekCount = weeks
                                useCustomWeeks = false
                            }

                            Toggle(
                                "Custom plan length",
                                isOn: $useCustomWeeks
                            )

                            if useCustomWeeks {
                                Stepper(
                                    "\(customWeeks) weeks",
                                    value: $customWeeks,
                                    in: 1...52
                                )
                                .padding(.top, 2)
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

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("PROGRAM WINDOW")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(1.4)
                                    .foregroundStyle(ATHLTHTheme.mutedText)

                                Text(
                                    "\(resolvedWeeks) " +
                                    (resolvedWeeks == 1 ? "week" : "weeks")
                                )
                                .font(.title3.weight(.bold))
                            }

                            Spacer()

                            Text(
                                "\(startDate.formatted(date: .abbreviated, time: .omitted))\n– \(resolvedEndDate.formatted(date: .abbreviated, time: .omitted))"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.mutedText)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if let conflict = conflictingPlan {
                    planConflictCard(
                        conflict,
                        message:
                            "Adjust the dates before creating this plan. ATHLTH keeps one active plan on each date."
                    )
                }

                if !goalStore.goals.isEmpty {
                    creationPanel(
                        eyebrow: "03 · GOALS",
                        title: "Connect goals",
                        subtitle:
                            "Optional. Linking goals makes progress and coaching context more useful.",
                        icon: "scope",
                        accent: ATHLTHTheme.vitality
                    ) {
                        VStack(spacing: 0) {
                            ForEach(
                                Array(goalStore.goals.enumerated()),
                                id: \.element.id
                            ) { index, goal in
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
                                        spacing: 3
                                    ) {
                                        Text(goal.title)
                                            .font(.subheadline.weight(.semibold))

                                        Text(goal.category.title)
                                            .font(.caption2)
                                            .foregroundStyle(ATHLTHTheme.mutedText)
                                    }
                                }
                                .padding(.vertical, 8)

                                if index < goalStore.goals.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                creationPanel(
                    eyebrow: goalStore.goals.isEmpty
                        ? "03 · WHAT COMES NEXT"
                        : "04 · WHAT COMES NEXT",
                    title: "Built for detailed programming",
                    subtitle:
                        "The new plan starts empty. Add only what belongs in it.",
                    icon: "slider.horizontal.3",
                    accent: ATHLTHTheme.accentDeep
                ) {
                    VStack(spacing: 10) {
                        advancedFeatureRow(
                            "Place any workout on any day",
                            icon: "calendar.badge.plus"
                        )
                        advancedFeatureRow(
                            "Strength exercises, sets, reps, load and progression",
                            icon: "dumbbell.fill"
                        )
                        advancedFeatureRow(
                            "Structured running, distance and routes",
                            icon: "figure.run"
                        )
                        advancedFeatureRow(
                            "Recovery, notes and scheduled time",
                            icon: "clock"
                        )
                    }
                }

                createPlanButton(
                    mode: .advanced,
                    title: "Create Empty Plan",
                    subtitle:
                        "\(resolvedWeeks) " +
                        (resolvedWeeks == 1 ? "week" : "weeks") +
                        " · ready for programming"
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(
            ATHLTHPremiumCanvas(
                accent: ATHLTHTheme.accent.opacity(0.30)
            )
        )
        .onChange(of: startDate) { _, newStart in
            if endDate < newStart {
                endDate = Calendar.current.date(
                    byAdding: .day,
                    value: 6,
                    to: newStart
                ) ?? newStart
            }
        }
    }

    private func builderIntro(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String,
        accent: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 54, height: 54)
                .background(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.15),
                            accent.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(
                        cornerRadius: 17,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(accent)

                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.97),
                    accent.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 25,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 25,
                style: .continuous
            )
            .stroke(Color.white.opacity(0.94), lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(0.045),
            radius: 14,
            y: 7
        )
    }

    private func creationPanel<Content: View>(
        eyebrow: String,
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(
                        accent.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(accent)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.98),
                    accent.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 23,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 23,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.96),
                lineWidth: 0.9
            )
        }
        .shadow(
            color: Color.black.opacity(0.038),
            radius: 12,
            y: 6
        )
    }

    private func premiumTextField(
        _ prompt: String,
        text: Binding<String>,
        axis: Axis = .horizontal
    ) -> some View {
        TextField(
            prompt,
            text: text,
            axis: axis
        )
        .textFieldStyle(.plain)
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.028),
            in: RoundedRectangle(
                cornerRadius: 13,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 13,
                style: .continuous
            )
            .stroke(Color.black.opacity(0.035), lineWidth: 0.8)
        }
    }

    private func durationChipGrid(
        options: [Int],
        selected: Int?,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: 78),
                    spacing: 8
                )
            ],
            spacing: 8
        ) {
            ForEach(options, id: \.self) { weeks in
                let isSelected = selected == weeks

                Button {
                    onSelect(weeks)
                } label: {
                    VStack(spacing: 3) {
                        Text("\(weeks)")
                            .font(.headline)
                        Text(weeks == 1 ? "week" : "weeks")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(
                        isSelected
                            ? Color.white
                            : ATHLTHTheme.primaryText
                    )
                    .background(
                        Group {
                            if isSelected {
                                LinearGradient(
                                    colors: [
                                        ATHLTHTheme.accent,
                                        ATHLTHTheme.accentDeep
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.88),
                                        Color.black.opacity(0.018)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                        },
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                        .stroke(
                            isSelected
                                ? Color.white.opacity(0.12)
                                : Color.black.opacity(0.035),
                            lineWidth: 0.8
                        )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func planConflictCard(
        _ conflict: TrainingPlan,
        message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 40, height: 40)
                .background(
                    Color.orange.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Overlaps with \(conflict.title)")
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(
            Color.orange.opacity(0.07),
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
            .stroke(Color.orange.opacity(0.12), lineWidth: 0.8)
        }
    }

    private func advancedFeatureRow(
        _ title: String,
        icon: String
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accent)
                .frame(width: 34, height: 34)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(
                    ATHLTHTheme.primaryText.opacity(0.84)
                )

            Spacer()
        }
    }

    private func createPlanButton(
        mode: TrainingPlanCreationMode,
        title: String,
        subtitle: String
    ) -> some View {
        let disabled =
            self.title
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty ||
            conflictingPlan != nil

        return Button {
            createPlan(mode: mode)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(
                        Color.white.opacity(0.14),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.accentDeep,
                        ATHLTHTheme.accent
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .shadow(
                color: ATHLTHTheme.accentDeep.opacity(
                    disabled ? 0.04 : 0.20
                ),
                radius: 15,
                y: 8
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
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
        let createdPlan: TrainingPlan?

        switch mode {
        case .simple:
            let autoSummary =
                "\(simpleFocus.title) · " +
                "\(simpleSessionsPerWeek) sessions per week"

            createdPlan = session.createSimpleTrainingPlan(
                title: title,
                summary: autoSummary,
                weekCount: simpleWeekCount,
                startDate: startDate,
                visibility: .privateOnly,
                sessionsPerWeek: simpleSessionsPerWeek,
                workoutPattern: simpleFocus.pattern
            )

        case .advanced:
            createdPlan = session.createTrainingPlan(
                title: title,
                summary: summary,
                weekCount: resolvedWeeks,
                startDate: startDate,
                endDate: resolvedEndDate,
                visibility: visibility
            )

            if let planID = createdPlan?.id {
                goalStore.setLinkedPlan(
                    planID,
                    goalIDs: selectedGoalIDs
                )
            }
        }

        guard createdPlan != nil else {
            if let conflict = conflictingPlan {
                creationError =
                    "This period overlaps with \(conflict.title). " +
                    "Adjust the dates so only one training plan is active at a time."
            } else {
                creationError =
                    "ATHLTH could not create this plan. Check the dates and try again."
            }
            return
        }

        dismiss()
    }

}

struct PlanMetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var spotify: SpotifyPlaybackStore

    let plan: TrainingPlan

    @State private var title: String
    @State private var summary: String
    @State private var visibility: ProfileVisibility
    @State private var tags: String
    @State private var startDate: Date
    @State private var weekCount: Int
    @State private var selectedGoalIDs: Set<UUID> = []
    @State private var selectedSpotifyPlaylist: SpotifyPlaylistReference?
    @State private var spotifyAutoplay: Bool
    @State private var showingSpotifyPlaylistPicker = false
    @State private var saveError: String?
    @State private var showingDeleteConfirmation = false

    init(plan: TrainingPlan) {
        self.plan = plan
        _title = State(initialValue: plan.title)
        _summary = State(initialValue: plan.summary)
        _visibility = State(initialValue: plan.visibility)
        _tags = State(initialValue: plan.tags.joined(separator: ", "))
        _startDate = State(
            initialValue:
                plan.startDate ??
                Calendar.current.startOfDay(for: Date())
        )
        _weekCount = State(initialValue: max(plan.weeks.count, 1))
        _selectedSpotifyPlaylist =
            State(initialValue: plan.spotifyPlaylist)
        _spotifyAutoplay =
            State(initialValue: plan.spotifyAutoplayOnWorkoutStart)
    }

    private var resolvedEndDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(weekCount * 7 - 1, 0),
            to: Calendar.current.startOfDay(for: startDate)
        ) ?? startDate
    }

    private var conflictingPlan: TrainingPlan? {
        session.trainingPlanConflict(
            startDate: startDate,
            endDate: resolvedEndDate,
            excludingPlanID: plan.id
        )
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

                    DatePicker(
                        "Program starts",
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    LabeledContent(
                        "Program ends",
                        value: resolvedEndDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                }

                if let conflict = conflictingPlan {
                    Section("Schedule Conflict") {
                        Label(
                            ATHLTHLocalization.format(
                                english: "Overlaps with %@",
                                norwegian: "Overlapper med %@",
                                conflict.title
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)

                        Text(
                            "Move this plan so it does not overlap another scheduled plan."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                Section("Spotify") {
                    if spotify.isConnected {
                        Button {
                            showingSpotifyPlaylistPicker = true
                        } label: {
                            LabeledContent {
                                Text(
                                    selectedSpotifyPlaylist?.name
                                        ?? "None"
                                )
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            } label: {
                                Label(
                                    "Workout playlist",
                                    systemImage: "music.note.list"
                                )
                            }
                        }
                        .buttonStyle(.plain)

                        if selectedSpotifyPlaylist != nil {
                            Toggle(
                                "Start playlist with workouts",
                                isOn: $spotifyAutoplay
                            )
                        }

                        Text(
                            "The linked playlist is used when a workout from this program starts on iPhone. Watch-only starts never wait for Spotify."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else if spotify.isConfigured {
                        Button {
                            spotify.connect()
                        } label: {
                            Label(
                                "Connect Spotify",
                                systemImage: "link"
                            )
                        }

                        Text(
                            "Connect Spotify to attach a playlist to this program."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(
                            "Spotify needs a client ID before playlists can be linked."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(
                        "Changing a program creates a new local version. Shared-program sync can use this version number later."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(
                            "Delete Program",
                            systemImage: "trash"
                        )
                        .frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text(
                        "Deleting the program removes its remaining plan and schedule. Completed workout history is kept."
                    )
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
                        let saved = session.updateTrainingPlan(
                            planID: plan.id,
                            title: title,
                            summary: summary,
                            visibility: visibility,
                            tags: tags
                                .split(separator: ",")
                                .map(String.init),
                            startDate: startDate,
                            weekCount: weekCount
                        )

                        guard saved else {
                            if let conflict = conflictingPlan {
                                saveError =
                                    "This period overlaps with \(conflict.title). Adjust the dates before saving."
                            } else {
                                saveError =
                                    "ATHLTH could not save the plan. Check the dates and try again."
                            }
                            return
                        }

                        goalStore.setLinkedPlan(
                            plan.id,
                            goalIDs: selectedGoalIDs
                        )

                        _ = session.setTrainingPlanSpotify(
                            planID: plan.id,
                            playlist: selectedSpotifyPlaylist,
                            autoplay: spotifyAutoplay
                        )

                        dismiss()
                    }
                    .disabled(
                        title
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty ||
                        conflictingPlan != nil
                    )
                }
            }
        }
        .sheet(isPresented: $showingSpotifyPlaylistPicker) {
            SpotifyPlaylistPickerView(
                title: "Program Playlist",
                selection: $selectedSpotifyPlaylist
            )
        }
        .confirmationDialog(
            ATHLTHLocalization.format(
                        english: "Delete %@?",
                        norwegian: "Slette %@?",
                        plan.title
                    ),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Program", role: .destructive) {
                goalStore.setLinkedPlan(
                    plan.id,
                    goalIDs: []
                )
                session.deleteTrainingPlan(plan.id)
                dismiss()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the program and its remaining schedule. Completed workout history is kept."
            )
        }
        .alert(
            "Plan Conflict",
            isPresented: Binding(
                get: { saveError != nil },
                set: { shown in
                    if !shown {
                        saveError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }
}

private enum SessionEditorMode: String, CaseIterable, Identifiable {
    case basic
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "Basic"
        case .advanced: return "Advanced"
        }
    }
}

private enum HeartRateTargetMode: String, CaseIterable, Identifiable {
    case zone
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zone: return "Zone"
        case .custom: return "Custom BPM"
        }
    }
}

struct SessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var gear: ProfileGearStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var health: HealthKitManager

    let dayID: UUID?
    let planID: UUID?
    let existingWorkout: PlannedSession?

    @State private var title = "New Workout"
    @State private var kind: WorkoutKind = .strength
    @State private var durationMinutes = 45
    @State private var distanceKilometers = 5.0
    @State private var notes = ""
    @State private var workoutTemplateID: UUID?
    @State private var workoutBlocks: [WorkoutTemplateBlock] = []
    @State private var workoutCategory: String?
    @State private var showingSavedWorkoutPicker = false

    @State private var plannedExercises: [PlannedExercise] = []
    @State private var exerciseBeingEdited: PlannedExercise?
    @State private var showingExerciseLibrary = false

    @State private var selectedRunningWorkouts: [RunningWorkoutTemplate] = []
    @State private var showingRunningLibrary = false
    @State private var selectedRouteID: UUID?

    @State private var scheduledTimeEnabled = false
    @State private var scheduledTime = Date()

    @State private var editorMode: SessionEditorMode = .basic
    @State private var selectedGearIDs: Set<UUID> = []
    @State private var gearSelectionTouched = false
    @State private var audioCoachOverride:
        WatchAudioCoachConfiguration? = nil
    @State private var showingAudioCoachEditor = false

    @State private var targetPaceEnabled = false
    @State private var targetPaceMinutes = 5
    @State private var targetPaceSeconds = 0

    @State private var heartRateTargetEnabled = false
    @State private var heartRateTargetMode:
        HeartRateTargetMode = .zone
    @State private var heartRateTargetZone = 2
    @State private var customHeartRateMinBPM = 120
    @State private var customHeartRateMaxBPM = 150
    @State private var paceAlertsEnabled = false
    @State private var paceAlertToleranceSeconds = 15
    @State private var targetAlertGraceSeconds = 30
    @State private var targetAlertRepeatSeconds = 120
    @State private var targetAlertDelivery:
        WatchAlertDelivery = .haptic
    @State private var targetAlertAnnounceBackInTarget = true

    init(dayID: UUID) {
        self.dayID = dayID
        self.planID = nil
        self.existingWorkout = nil
    }

    init(
        planID: UUID,
        dayID: UUID
    ) {
        self.dayID = dayID
        self.planID = planID
        self.existingWorkout = nil
    }

    init(
        planID: UUID,
        workout: PlannedSession
    ) {
        self.dayID = nil
        self.planID = planID
        self.existingWorkout = workout

        _title = State(initialValue: workout.title)
        _kind = State(initialValue: workout.kind)
        _durationMinutes = State(
            initialValue: workout.durationMinutes ?? 45
        )
        _distanceKilometers = State(
            initialValue: workout.targetDistanceKilometers ?? 5.0
        )
        _notes = State(initialValue: workout.notes ?? "")
        _workoutTemplateID = State(
            initialValue: workout.workoutTemplateID
        )
        _workoutBlocks = State(
            initialValue: workout.resolvedWorkoutBlocks
        )
        _workoutCategory = State(
            initialValue: workout.workoutCategory
        )
        _plannedExercises = State(initialValue: workout.exercises)
        _selectedRunningWorkouts = State(
            initialValue: workout.resolvedRunningWorkouts
        )
        _selectedRouteID = State(initialValue: workout.routeID)
        _scheduledTimeEnabled = State(
            initialValue: workout.scheduledStart != nil
        )
        _scheduledTime = State(
            initialValue: workout.scheduledStart ?? Date()
        )
        _selectedGearIDs = State(
            initialValue: Set(workout.gearIDs ?? [])
        )
        _audioCoachOverride = State(
            initialValue: workout.audioCoachConfiguration
        )

        if let target =
                workout.targetAlertConfiguration {
            _heartRateTargetEnabled = State(
                initialValue: target.heartRateEnabled
            )
            _heartRateTargetZone = State(
                initialValue:
                    min(
                        max(target.heartRateZone ?? 2, 1),
                        5
                    )
            )
            _heartRateTargetMode = State(
                initialValue:
                    target.heartRateZone == nil
                        ? .custom
                        : .zone
            )
            _customHeartRateMinBPM = State(
                initialValue:
                    Int(
                        target.heartRateMinimumBPM?
                            .rounded() ?? 120
                    )
            )
            _customHeartRateMaxBPM = State(
                initialValue:
                    Int(
                        target.heartRateMaximumBPM?
                            .rounded() ?? 150
                    )
            )
            _paceAlertsEnabled = State(
                initialValue:
                    target.paceAlertsEnabled
            )
            _paceAlertToleranceSeconds = State(
                initialValue:
                    Int(
                        target
                            .paceToleranceSecondsPerKilometer
                            .rounded()
                    )
            )
            _targetAlertGraceSeconds = State(
                initialValue:
                    Int(target.graceSeconds.rounded())
            )
            _targetAlertRepeatSeconds = State(
                initialValue:
                    Int(target.repeatSeconds.rounded())
            )
            _targetAlertDelivery = State(
                initialValue: target.delivery
            )
            _targetAlertAnnounceBackInTarget = State(
                initialValue:
                    target.announceBackInTarget
            )
        }

        if let pace = workout.targetPaceSecondsPerKilometer,
           pace > 0 {
            let total = max(Int(pace.rounded()), 0)
            _targetPaceEnabled = State(initialValue: true)
            _targetPaceMinutes = State(
                initialValue: total / 60
            )
            _targetPaceSeconds = State(
                initialValue: total % 60
            )
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if existingWorkout == nil {
                    Section("Start from") {
                        Button {
                            showingSavedWorkoutPicker = true
                        } label: {
                            HStack(spacing: 11) {
                                Image(
                                    systemName:
                                        "rectangle.stack.fill"
                                )
                                .foregroundStyle(
                                    ATHLTHTheme.accent
                                )
                                .frame(width: 28)

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text("My Workouts")
                                        .foregroundStyle(
                                            ATHLTHTheme.primaryText
                                        )

                                    Text(
                                        "Use a complete saved workout as this plan session."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(
                                    systemName: "chevron.right"
                                )
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !workoutBlocks.isEmpty {
                    Section("Workout Structure") {
                        HStack {
                            Label(
                                "\(workoutBlocks.count) blocks",
                                systemImage:
                                    "list.number"
                            )

                            Spacer()

                            if let workoutCategory {
                                Text(
                                    workoutCategory.capitalized
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(
                            workoutBlocks.prefix(5)
                        ) { block in
                            HStack(spacing: 10) {
                                Image(
                                    systemName:
                                        block.kind.systemImage
                                )
                                .foregroundStyle(
                                    block.kind == .run
                                        ? ATHLTHTheme.vitality
                                        : ATHLTHTheme.accent
                                )
                                .frame(width: 24)

                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(block.title)
                                        .font(.subheadline)

                                    if let target =
                                        block.targetText {
                                        Text(target)
                                            .font(.caption2)
                                            .foregroundStyle(
                                                .secondary
                                            )
                                    }
                                }

                                Spacer()
                            }
                        }

                        if workoutBlocks.count > 5 {
                            Text(
                                "+\(workoutBlocks.count - 5) more blocks"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
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

                    HStack {
                        Label("Time", systemImage: "clock")
                            .foregroundStyle(
                                ATHLTHTheme.primaryText
                            )

                        Spacer()

                        if scheduledTimeEnabled {
                            DatePicker(
                                "",
                                selection: $scheduledTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()

                            Button {
                                scheduledTimeEnabled = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear workout time")
                        } else {
                            Button("–") {
                                scheduledTime = Date()
                                scheduledTimeEnabled = true
                            }
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme.mutedText
                            )
                            .buttonStyle(.plain)
                            .accessibilityLabel("Set workout time")
                        }
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

                    if kind == .running {
                        Picker(
                            "Running shoes",
                            selection: runningShoeSelection
                        ) {
                            Text("–")
                                .tag(nil as UUID?)

                            ForEach(activeRunningShoes) { shoe in
                                Text(
                                    shoe.id ==
                                        gear.defaultRunningShoe?.id
                                        ? "\(shoe.name) · Default"
                                        : shoe.name
                                )
                                .tag(shoe.id as UUID?)
                            }
                        }
                    }

                    TextField(
                        "Notes",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                } header: {
                    HStack(spacing: 12) {
                        Text("Workout")

                        Spacer()

                        Picker(
                            "Editor mode",
                            selection: $editorMode
                        ) {
                            ForEach(
                                SessionEditorMode.allCases
                            ) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                        .labelsHidden()
                    }
                    .textCase(nil)
                }

                if editorMode == .advanced {
                    advancedOptions
                }

                if kind == .strength {
                    strengthBuilder
                }

                if kind == .running {
                    runningBuilder
                    routeBuilder
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
            .navigationTitle(existingWorkout == nil ? "Add Session" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(existingWorkout == nil ? "Add" : "Save") {
                        saveSession()
                    }
                    .disabled(!canAdd)
                }
            }
            .sheet(isPresented: $showingSavedWorkoutPicker) {
                SavedWorkoutPickerView { workout in
                    applySavedWorkout(workout)
                    showingSavedWorkoutPicker = false
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
                        selectionTitle: "Add to Plan"
                    ) { workout in
                        addRunningWorkout(workout)
                    }
                }
            }
            .sheet(isPresented: $showingAudioCoachEditor) {
                PlannedAudioCoachEditorView(
                    configuration: $audioCoachOverride,
                    defaultConfiguration:
                        settings.audioCoachConfiguration(
                            enabled:
                                settings.audioCoachEnabledByDefault
                        )
                )
            }
            .onChange(of: kind) { _, newKind in
                guard existingWorkout == nil else { return }

                if newKind == .strength && title == "New Workout" {
                    title = "Strength Workout"
                } else if newKind == .running && title == "New Workout" {
                    title = "Running Workout"
                } else if newKind == .walking && title == "New Workout" {
                    title = "Walk"
                }
            }
            .onChange(of: selectedRouteID) { oldRouteID, newRouteID in
                syncMetricsFromRouteChange(
                    previousRouteID: oldRouteID,
                    routeID: newRouteID
                )
            }
            .task {
                await gear.refresh()
                applyDefaultRunningShoeIfNeeded()
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .running {
                    applyDefaultRunningShoeIfNeeded()
                }
            }
        }
    }

    @ViewBuilder
    private var advancedOptions: some View {
        if kind == .running {
            Section("Performance") {
                Toggle(
                    "Target pace",
                    isOn: $targetPaceEnabled
                )

                if targetPaceEnabled {
                    HStack {
                        Label(
                            "Pace",
                            systemImage: "speedometer"
                        )

                        Spacer()

                        Stepper(
                            value: $targetPaceMinutes,
                            in: 2...15
                        ) {
                            Text(
                                "\(targetPaceMinutes):\(String(format: "%02d", targetPaceSeconds)) /km"
                            )
                            .monospacedDigit()
                        }
                    }

                    Stepper(
                        "Pace seconds: \(targetPaceSeconds)",
                        value: $targetPaceSeconds,
                        in: 0...55,
                        step: 5
                    )
                }
            }

        }

        if kind == .running || kind == .walking {
            Section("Live Targets & Alerts") {
                Toggle(
                    "Heart-rate target",
                    isOn: $heartRateTargetEnabled
                )

                if heartRateTargetEnabled {
                    Picker(
                        "Heart-rate target",
                        selection: $heartRateTargetMode
                    ) {
                        ForEach(
                            HeartRateTargetMode.allCases
                        ) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if heartRateTargetMode == .zone {
                        Picker(
                            "Zone",
                            selection: $heartRateTargetZone
                        ) {
                            ForEach(1...5, id: \.self) { zone in
                                Text(ATHLTHLocalization.format(
                                    english: "Zone %d",
                                    norwegian: "Sone %d",
                                    zone
                                ))
                                    .tag(zone)
                            }
                        }

                        if let range =
                                heartRateRange(
                                    for: heartRateTargetZone
                                ) {
                            LabeledContent(
                                "Target range",
                                value:
                                    "\(range.lower)–\(range.upper) bpm"
                            )

                            Text(
                                session.onboardingProfile?.maximumHeartRateBPM != nil
                                    ? "ATHLTH uses your saved maximum heart rate from Health Profile as the source of truth for this zone."
                                    : resolvedMaximumHeartRate != nil
                                        ? "ATHLTH estimates maximum heart rate from your age because no known max is saved in Health Profile."
                                        : "Using the saved BPM range for this zone. Add a known max heart rate or date of birth in Health Profile to calculate zones."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(
                                "Add a known maximum heart rate or date of birth in Health Profile to calculate zones, or choose Custom BPM."
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    } else {
                        Stepper(
                            "Minimum: \(customHeartRateMinBPM) bpm",
                            value: $customHeartRateMinBPM,
                            in: 60...230,
                            step: 1
                        )

                        Stepper(
                            "Maximum: \(customHeartRateMaxBPM) bpm",
                            value: $customHeartRateMaxBPM,
                            in: 70...240,
                            step: 1
                        )
                    }
                }

                if kind == .running &&
                    targetPaceEnabled {
                    Toggle(
                        "Alert outside pace target",
                        isOn: $paceAlertsEnabled
                    )

                    if paceAlertsEnabled {
                        Picker(
                            "Pace tolerance",
                            selection:
                                $paceAlertToleranceSeconds
                        ) {
                            Text("± 5 sec /km").tag(5)
                            Text("± 10 sec /km").tag(10)
                            Text("± 15 sec /km").tag(15)
                            Text("± 30 sec /km").tag(30)
                        }
                    }
                }

                if hasLiveTargetAlerts {
                    Picker(
                        "Wait before alert",
                        selection:
                            $targetAlertGraceSeconds
                    ) {
                        Text("Immediately").tag(0)
                        Text("15 sec").tag(15)
                        Text("30 sec").tag(30)
                        Text("1 min").tag(60)
                    }

                    Picker(
                        "Alert style",
                        selection:
                            $targetAlertDelivery
                    ) {
                        ForEach(
                            WatchAlertDelivery.allCases
                        ) { delivery in
                            Text(delivery.title)
                                .tag(delivery)
                        }
                    }

                    Picker(
                        "Repeat while outside target",
                        selection:
                            $targetAlertRepeatSeconds
                    ) {
                        Text("30 sec").tag(30)
                        Text("1 min").tag(60)
                        Text("2 min").tag(120)
                        Text("5 min").tag(300)
                    }

                    Toggle(
                        "Tell me when I'm back in target",
                        isOn:
                            $targetAlertAnnounceBackInTarget
                    )
                }

                Text(
                    "These targets apply only to this workout. Route-deviation alerts use your global Training settings."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }

        if kind == .running || kind == .walking {
            Section("Audio Coach") {
                Button {
                    showingAudioCoachEditor = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.and.person.filled")
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Audio Coach")
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )

                            Text(audioCoachStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Text(
                    "Use the app default or customize cues for this workout only."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }

        Section("Additional Gear") {
            if additionalGearItems.isEmpty {
                Text(
                    "No additional active gear is available. Add watches, headphones or other gear in My Gear."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ForEach(additionalGearItems) { item in
                    Button {
                        toggleGear(item.id)
                    } label: {
                        HStack(spacing: 11) {
                            Image(
                                systemName: item.category.systemImage
                            )
                            .foregroundStyle(ATHLTHTheme.accent)
                            .frame(width: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .foregroundStyle(
                                        ATHLTHTheme.primaryText
                                    )

                                Text(item.category.shortTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(
                                systemName:
                                    selectedGearIDs.contains(item.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                            )
                            .foregroundStyle(
                                selectedGearIDs.contains(item.id)
                                    ? ATHLTHTheme.vitality
                                    : ATHLTHTheme.mutedText
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(
                "Selected gear is linked automatically when the workout is completed."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var hasLiveTargetAlerts: Bool {
        heartRateTargetEnabled ||
        (
            kind == .running &&
            targetPaceEnabled &&
            paceAlertsEnabled
        )
    }

    private var resolvedMaximumHeartRate: Double? {
        if let known =
                session
                    .onboardingProfile?
                    .maximumHeartRateBPM,
           known >= 100,
           known <= 240 {
            return Double(known)
        }

        let dateOfBirth =
            session.onboardingProfile?.dateOfBirth ??
            health.personalDetails.dateOfBirth

        guard let dateOfBirth else {
            return nil
        }

        let age = Calendar.current
            .dateComponents(
                [.year],
                from: dateOfBirth,
                to: Date()
            )
            .year ?? 0

        guard age >= 13,
              age <= 100
        else {
            return nil
        }

        return max(
            100,
            208 - (0.7 * Double(age))
        )
    }

    private func estimatedHeartRateRange(
        for zone: Int
    ) -> (lower: Int, upper: Int)? {
        guard let maximum =
                resolvedMaximumHeartRate
        else {
            return nil
        }

        let bounds: (Double, Double)

        switch min(max(zone, 1), 5) {
        case 1:
            bounds = (0.50, 0.60)
        case 2:
            bounds = (0.60, 0.70)
        case 3:
            bounds = (0.70, 0.80)
        case 4:
            bounds = (0.80, 0.90)
        default:
            bounds = (0.90, 1.00)
        }

        return (
            lower:
                Int(
                    (maximum * bounds.0)
                        .rounded()
                ),
            upper:
                Int(
                    (maximum * bounds.1)
                        .rounded()
                )
        )
    }

    private func heartRateRange(
        for zone: Int
    ) -> (lower: Int, upper: Int)? {
        if let estimated =
                estimatedHeartRateRange(
                    for: zone
                ) {
            return estimated
        }

        guard let existing =
                existingWorkout?
                    .targetAlertConfiguration,
              existing.heartRateEnabled,
              existing.heartRateZone == zone,
              let minimum =
                existing.heartRateMinimumBPM,
              let maximum =
                existing.heartRateMaximumBPM
        else {
            return nil
        }

        return (
            lower: Int(minimum.rounded()),
            upper: Int(maximum.rounded())
        )
    }

    private var workoutTargetAlertConfigurationForSave:
        WatchWorkoutTargetAlertConfiguration? {
        let paceEnabled =
            kind == .running &&
            targetPaceEnabled &&
            paceAlertsEnabled

        let heartRange:
            (
                zone: Int?,
                lower: Double,
                upper: Double
            )? = {
            guard heartRateTargetEnabled else {
                return nil
            }

            switch heartRateTargetMode {
            case .zone:
                guard let range =
                        heartRateRange(
                            for: heartRateTargetZone
                        )
                else {
                    return nil
                }

                return (
                    zone: heartRateTargetZone,
                    lower: Double(range.lower),
                    upper: Double(range.upper)
                )

            case .custom:
                let lower =
                    min(
                        customHeartRateMinBPM,
                        customHeartRateMaxBPM
                    )
                let upper =
                    max(
                        customHeartRateMinBPM,
                        customHeartRateMaxBPM
                    )

                return (
                    zone: nil,
                    lower: Double(lower),
                    upper: Double(upper)
                )
            }
        }()

        guard heartRange != nil ||
                paceEnabled
        else {
            return nil
        }

        return WatchWorkoutTargetAlertConfiguration(
            heartRateEnabled:
                heartRange != nil,
            heartRateZone:
                heartRange?.zone,
            heartRateMinimumBPM:
                heartRange?.lower,
            heartRateMaximumBPM:
                heartRange?.upper,
            paceAlertsEnabled:
                paceEnabled,
            paceToleranceSecondsPerKilometer:
                Double(
                    max(
                        paceAlertToleranceSeconds,
                        0
                    )
                ),
            graceSeconds:
                TimeInterval(
                    max(
                        targetAlertGraceSeconds,
                        0
                    )
                ),
            repeatSeconds:
                TimeInterval(
                    max(
                        targetAlertRepeatSeconds,
                        30
                    )
                ),
            delivery:
                targetAlertDelivery,
            announceBackInTarget:
                targetAlertAnnounceBackInTarget
        )
    }

    private var activeRunningShoes: [ProfileGearItem] {
        gear.items(in: .shoes).filter {
            gear.isActive($0)
        }
    }

    private var runningShoeSelection: Binding<UUID?> {
        Binding(
            get: {
                activeRunningShoes.first {
                    selectedGearIDs.contains($0.id)
                }?.id
            },
            set: { newValue in
                gearSelectionTouched = true

                let shoeIDs = Set(
                    gear.items(in: .shoes).map(\.id)
                )

                selectedGearIDs.subtract(shoeIDs)

                if let newValue {
                    selectedGearIDs.insert(newValue)
                }
            }
        )
    }

    private var additionalGearItems: [ProfileGearItem] {
        gear.items.filter {
            gear.isActive($0) &&
            $0.category != .shoes
        }
        .sorted {
            if $0.category != $1.category {
                return $0.category.rawValue <
                    $1.category.rawValue
            }

            return $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    private var plannedGearIDsForSave: [UUID]? {
        let allowed = selectedGearIDs.filter { id in
            guard let item = gear.items.first(
                where: { $0.id == id }
            ) else {
                return true
            }

            return item.category != .shoes ||
                kind == .running
        }

        if allowed.isEmpty &&
            !gearSelectionTouched &&
            existingWorkout?.gearIDs == nil {
            return nil
        }

        return allowed.sorted {
            $0.uuidString < $1.uuidString
        }
    }

    private var audioCoachStatusText: String {
        if let configuration = audioCoachOverride {
            return configuration.enabled
                ? "Custom · On"
                : "Custom · Off"
        }

        return settings.audioCoachEnabledByDefault
            ? "App default · On"
            : "App default · Off"
    }

    private func toggleGear(_ id: UUID) {
        gearSelectionTouched = true

        if selectedGearIDs.contains(id) {
            selectedGearIDs.remove(id)
        } else {
            selectedGearIDs.insert(id)
        }
    }

    private func applyDefaultRunningShoeIfNeeded() {
        guard kind == .running,
              existingWorkout == nil,
              runningShoeSelection.wrappedValue == nil,
              let defaultShoe = gear.defaultRunningShoe
        else {
            return
        }

        selectedGearIDs.insert(defaultShoe.id)
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
        Section("Running Workout") {
            if selectedRunningWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.run")
                            .foregroundStyle(ATHLTHTheme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open run")
                                .font(.subheadline.weight(.semibold))

                            Text(
                                "Use the duration and distance above, or add one or more structured workouts."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showingRunningLibrary = true
                    } label: {
                        Label(
                            "Add Structured Running Workout",
                            systemImage: "plus.circle.fill"
                        )
                    }
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            selectedRunningWorkouts.count == 1
                                ? "1 structured workout"
                                : "\(selectedRunningWorkouts.count) structured workouts"
                        )
                        .font(.subheadline.weight(.semibold))

                        Text(runningSelectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showingRunningLibrary = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ForEach(
                    Array(selectedRunningWorkouts.enumerated()),
                    id: \.element.id
                ) { index, workout in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: workout.type.systemImage)
                                .foregroundStyle(ATHLTHTheme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(runningWorkoutMetricSummary(workout))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                removeRunningWorkout(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                ATHLTHLocalization.format(
                        english: "Remove %@",
                        norwegian: "Fjern %@",
                        workout.title
                    )
                            )
                        }

                        DisclosureGroup("Workout structure") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(
                                    Array(workout.blocks.enumerated()),
                                    id: \.element.id
                                ) { blockIndex, block in
                                    RunningWorkoutBlockRow(
                                        index: blockIndex + 1,
                                        block: block
                                    )
                                }
                            }
                            .padding(.top, 8)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private var selectedRoute: TrainingRoute? {
        guard let selectedRouteID else {
            return nil
        }

        return session.savedRoutes.first {
            $0.id == selectedRouteID
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

            if let selectedRoute {
                HStack(spacing: 8) {
                    Label(
                        String(
                            format: "%.1f km",
                            selectedRoute.distanceKilometers
                        ),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )

                    if kind == .walking,
                       let seconds =
                            selectedRoute.expectedTravelTimeSeconds {
                        Label(
                            ATHLTHLocalization.format(
                                    english: "%d min",
                                    norwegian: "%d min",
                                    max(Int((seconds / 60).rounded()), 1)
                                ),
                            systemImage: "timer"
                        )
                    }

                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var runningSelectionSummary: String {
        var parts: [String] = []

        let distanceValues =
            selectedRunningWorkouts
                .compactMap(\.estimatedDistanceMeters)

        if distanceValues.count == selectedRunningWorkouts.count,
           !distanceValues.isEmpty {
            let kilometers =
                distanceValues.reduce(0, +) / 1_000
            parts.append(
                String(format: "%.1f km", kilometers)
            )
        }

        let durationValues =
            selectedRunningWorkouts
                .compactMap(\.estimatedDurationSeconds)

        if durationValues.count == selectedRunningWorkouts.count,
           !durationValues.isEmpty {
            let minutes = Int(
                (durationValues.reduce(0, +) / 60).rounded()
            )
            parts.append("\(minutes) min")
        }

        return parts.isEmpty
            ? "Totals can be adjusted manually above."
            : parts.joined(separator: " · ")
    }

    private func runningWorkoutMetricSummary(
        _ workout: RunningWorkoutTemplate
    ) -> String {
        var parts = [
            workout.type.title,
            "\(workout.blocks.count) blocks"
        ]

        if let distance = workout.estimatedDistanceMeters {
            parts.append(
                String(
                    format: "%.1f km",
                    distance / 1_000
                )
            )
        }

        if let duration = workout.estimatedDurationSeconds {
            parts.append(
                "\(Int((duration / 60).rounded())) min"
            )
        }

        return parts.joined(separator: " · ")
    }

    private func addRunningWorkout(
        _ workout: RunningWorkoutTemplate
    ) {
        guard !selectedRunningWorkouts.contains(
            where: { $0.id == workout.id }
        ) else {
            return
        }

        let wasEmpty = selectedRunningWorkouts.isEmpty
        selectedRunningWorkouts.append(workout)

        if wasEmpty,
           title == "New Workout" ||
           title == "Running Workout" ||
           title == "Walk" {
            title = workout.title
        }

        syncRunningMetricsFromSelection()
    }

    private func removeRunningWorkout(
        at index: Int
    ) {
        guard selectedRunningWorkouts.indices.contains(index)
        else {
            return
        }

        selectedRunningWorkouts.remove(at: index)
        syncRunningMetricsFromSelection()
    }

    private func syncRunningMetricsFromSelection() {
        guard !selectedRunningWorkouts.isEmpty else {
            return
        }

        let distanceValues =
            selectedRunningWorkouts
                .compactMap(\.estimatedDistanceMeters)

        let durationValues =
            selectedRunningWorkouts
                .compactMap(\.estimatedDurationSeconds)

        let hasCompleteDistance =
            distanceValues.count == selectedRunningWorkouts.count
        let hasCompleteDuration =
            durationValues.count == selectedRunningWorkouts.count

        if let selectedRoute {
            // A selected route defines the actual planned distance.
            distanceKilometers =
                selectedRoute.distanceKilometers

            if hasCompleteDuration {
                let totalSeconds =
                    durationValues.reduce(0, +)

                if hasCompleteDistance {
                    let totalMeters =
                        distanceValues.reduce(0, +)

                    if totalMeters > 0 {
                        let secondsPerMeter =
                            totalSeconds / totalMeters
                        durationMinutes = max(
                            5,
                            Int(
                                (
                                    selectedRoute.distanceKilometers *
                                    1_000 *
                                    secondsPerMeter /
                                    60
                                )
                                .rounded()
                            )
                        )
                    }
                } else {
                    // Time-based structured workouts already define the
                    // intended session duration even if distance is route-led.
                    durationMinutes = max(
                        5,
                        Int((totalSeconds / 60).rounded())
                    )
                }
            }

            return
        }

        if hasCompleteDistance {
            distanceKilometers =
                distanceValues.reduce(0, +) / 1_000
        }

        if hasCompleteDuration {
            durationMinutes = max(
                5,
                Int(
                    (durationValues.reduce(0, +) / 60)
                        .rounded()
                )
            )
        }
    }

    private func syncMetricsFromRouteChange(
        previousRouteID: UUID?,
        routeID: UUID?
    ) {
        guard let routeID else {
            if kind == .running,
               !selectedRunningWorkouts.isEmpty {
                syncRunningMetricsFromSelection()
            }
            return
        }

        guard let route = session.savedRoutes.first(
            where: { $0.id == routeID }
        ) else {
            return
        }

        let previousDistance = max(
            distanceKilometers,
            0.01
        )
        let previousDuration = max(
            durationMinutes,
            1
        )

        distanceKilometers = route.distanceKilometers

        if kind == .walking {
            if let seconds = route.expectedTravelTimeSeconds,
               seconds > 0 {
                durationMinutes = max(
                    5,
                    Int((seconds / 60).rounded())
                )
            }
            return
        }

        guard kind == .running else {
            return
        }

        let distanceValues =
            selectedRunningWorkouts
                .compactMap(\.estimatedDistanceMeters)
        let durationValues =
            selectedRunningWorkouts
                .compactMap(\.estimatedDurationSeconds)

        let hasCompleteDistance =
            !selectedRunningWorkouts.isEmpty &&
            distanceValues.count == selectedRunningWorkouts.count
        let hasCompleteDuration =
            !selectedRunningWorkouts.isEmpty &&
            durationValues.count == selectedRunningWorkouts.count

        if hasCompleteDuration {
            let totalSeconds =
                durationValues.reduce(0, +)

            if hasCompleteDistance {
                let totalMeters =
                    distanceValues.reduce(0, +)

                if totalMeters > 0 {
                    durationMinutes = max(
                        5,
                        Int(
                            (
                                route.distanceKilometers *
                                1_000 *
                                totalSeconds /
                                totalMeters /
                                60
                            )
                            .rounded()
                        )
                    )
                    return
                }
            }

            durationMinutes = max(
                5,
                Int((totalSeconds / 60).rounded())
            )
            return
        }

        // No reliable running duration exists on the saved route itself
        // (Apple Maps stores a walking estimate). Preserve the user's
        // current implied pace when switching to a different run route.
        let impliedMinutesPerKilometer =
            Double(previousDuration) /
            previousDistance

        durationMinutes = max(
            5,
            Int(
                (
                    route.distanceKilometers *
                    impliedMinutesPerKilometer
                )
                .rounded()
            )
        )
    }


    private func applySavedWorkout(
        _ workout: PlannedSession
    ) {
        title = workout.title
        kind = workout.kind
        durationMinutes =
            workout.durationMinutes ?? durationMinutes
        distanceKilometers =
            workout.targetDistanceKilometers ??
            distanceKilometers
        notes = workout.notes ?? ""
        plannedExercises = workout.exercises
        selectedRunningWorkouts =
            workout.resolvedRunningWorkouts
        selectedRouteID = workout.routeID
        selectedGearIDs = Set(workout.gearIDs ?? [])
        gearSelectionTouched = workout.gearIDs != nil
        audioCoachOverride =
            workout.audioCoachConfiguration
        workoutTemplateID =
            workout.workoutTemplateID
        workoutBlocks =
            workout.resolvedWorkoutBlocks
        workoutCategory =
            workout.workoutCategory

        if let scheduled = workout.scheduledStart {
            scheduledTimeEnabled = true
            scheduledTime = scheduled
        }

        if let pace =
                workout.targetPaceSecondsPerKilometer,
           pace > 0 {
            let total = max(
                Int(pace.rounded()),
                0
            )
            targetPaceEnabled = true
            targetPaceMinutes = total / 60
            targetPaceSeconds = total % 60
        }
    }

    private func saveSession() {
        let cleanNotes = notes
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let workout = PlannedSession(
            id: existingWorkout?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            scheduledStart: scheduledTimeEnabled
                ? scheduledTime
                : nil,
            durationMinutes: durationMinutes,
            targetDistanceKilometers:
                (kind == .walking || kind == .running)
                    ? distanceKilometers
                    : nil,
            targetPaceSecondsPerKilometer:
                kind == .running &&
                targetPaceEnabled
                    ? Double(
                        targetPaceMinutes * 60 +
                        targetPaceSeconds
                    )
                    : nil,
            routeID: selectedRouteID,
            exercises: kind == .strength
                ? plannedExercises
                : [],
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            runningWorkout: kind == .running
                ? selectedRunningWorkouts.first
                : nil,
            runningWorkouts: kind == .running
                ? selectedRunningWorkouts
                : nil,
            gearIDs: plannedGearIDsForSave,
            audioCoachConfiguration:
                (kind == .running || kind == .walking)
                    ? audioCoachOverride
                    : nil,
            targetAlertConfiguration:
                (kind == .running || kind == .walking)
                    ? workoutTargetAlertConfigurationForSave
                    : nil,
            workoutTemplateID:
                workoutTemplateID,
            workoutBlocks:
                workoutBlocks.isEmpty
                    ? nil
                    : workoutBlocks,
            workoutCategory:
                workoutCategory
        )

        if existingWorkout != nil,
           let planID {
            session.updateSession(
                workout,
                inPlan: planID
            )
        } else if let dayID {
            if let planID {
                session.addSession(
                    workout,
                    toDay: dayID,
                    inPlan: planID
                )
            } else {
                session.addSession(
                    workout,
                    toDay: dayID
                )
            }
        }

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

private struct PlannedAudioCoachEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var configuration:
        WatchAudioCoachConfiguration?

    let defaultConfiguration:
        WatchAudioCoachConfiguration

    @State private var usesCustomSettings: Bool
    @State private var draft:
        WatchAudioCoachConfiguration

    init(
        configuration:
            Binding<WatchAudioCoachConfiguration?>,
        defaultConfiguration:
            WatchAudioCoachConfiguration
    ) {
        _configuration = configuration
        self.defaultConfiguration =
            defaultConfiguration

        let existing =
            configuration.wrappedValue

        _usesCustomSettings = State(
            initialValue: existing != nil
        )
        _draft = State(
            initialValue:
                existing ??
                defaultConfiguration
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Customize for this workout",
                        isOn: $usesCustomSettings
                    )

                    Text(
                        usesCustomSettings
                            ? "These settings apply only to this planned workout."
                            : "ATHLTH will use your Audio Coach defaults from Settings."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if usesCustomSettings {
                    Section("Audio Coach") {
                        Toggle(
                            "Audio Coach",
                            isOn: $draft.enabled
                        )

                        Picker(
                            "Language",
                            selection: $draft.language
                        ) {
                            ForEach(
                                WatchAudioCoachLanguage
                                    .allCases,
                                id: \.self
                            ) { language in
                                Text(language.title)
                                    .tag(language)
                            }
                        }
                    }

                    if draft.enabled {
                        Section("When to speak") {
                            Toggle(
                                "Distance interval",
                                isOn:
                                    distanceTriggerBinding
                            )

                            if draft
                                .distanceIntervalMeters != nil {
                                Stepper(
                                    distanceIntervalLabel,
                                    value:
                                        distanceIntervalBinding,
                                    in: 250...10_000,
                                    step: 250
                                )
                            }

                            Toggle(
                                "Time interval",
                                isOn: timeTriggerBinding
                            )

                            if draft
                                .timeIntervalSeconds != nil {
                                Stepper(
                                    timeIntervalLabel,
                                    value:
                                        timeIntervalBinding,
                                    in: 60...3_600,
                                    step: 60
                                )
                            }
                        }

                        Section("Announcements") {
                            Toggle(
                                "Distance",
                                isOn:
                                    $draft
                                        .announceDistance
                            )
                            Toggle(
                                "Elapsed time",
                                isOn:
                                    $draft
                                        .announceElapsedTime
                            )
                            Toggle(
                                "Average pace",
                                isOn:
                                    $draft
                                        .announceAveragePace
                            )
                            Toggle(
                                "Clock time",
                                isOn:
                                    $draft
                                        .announceClockTime
                            )
                            Toggle(
                                "Heart rate",
                                isOn:
                                    $draft
                                        .announceHeartRate
                            )
                            Toggle(
                                "Remaining route distance",
                                isOn:
                                    $draft
                                        .announceRemainingRouteDistance
                            )
                            Toggle(
                                "Estimated route time left",
                                isOn:
                                    $draft
                                        .announceEstimatedRemainingRouteTime
                            )
                            Toggle(
                                "Current workout step",
                                isOn:
                                    $draft
                                        .announceCurrentWorkoutStep
                            )
                            Toggle(
                                "Remaining step time",
                                isOn:
                                    $draft
                                        .announceRemainingStepTime
                            )
                            Toggle(
                                "Remaining step distance",
                                isOn:
                                    $draft
                                        .announceRemainingStepDistance
                            )
                        }

                        Section("Music & other audio") {
                            Toggle(
                                "Lower music while coach speaks",
                                isOn: Binding(
                                    get: {
                                        draft.shouldDuckOtherAudio
                                    },
                                    set: { enabled in
                                        draft.duckOtherAudio = enabled
                                    }
                                )
                            )

                            Text(
                                draft.shouldDuckOtherAudio
                                    ? "Spotify and other audio are reduced only while the coach is speaking."
                                    : "Coach speech mixes with other audio at its current level."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Audio Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Save") {
                        if usesCustomSettings {
                            var saved = draft
                            saved.routeDistanceMeters = nil
                            configuration = saved
                        } else {
                            configuration = nil
                        }

                        dismiss()
                    }
                }
            }
            .onChange(
                of: usesCustomSettings
            ) { _, enabled in
                if enabled &&
                    configuration == nil {
                    draft = defaultConfiguration
                }
            }
        }
    }

    private var distanceTriggerBinding:
        Binding<Bool> {
        Binding(
            get: {
                draft.distanceIntervalMeters != nil
            },
            set: { enabled in
                draft.distanceIntervalMeters =
                    enabled
                        ? (
                            draft
                                .distanceIntervalMeters ??
                            defaultConfiguration
                                .distanceIntervalMeters ??
                            1_000
                        )
                        : nil
            }
        )
    }

    private var timeTriggerBinding:
        Binding<Bool> {
        Binding(
            get: {
                draft.timeIntervalSeconds != nil
            },
            set: { enabled in
                draft.timeIntervalSeconds =
                    enabled
                        ? (
                            draft
                                .timeIntervalSeconds ??
                            defaultConfiguration
                                .timeIntervalSeconds ??
                            600
                        )
                        : nil
            }
        )
    }

    private var distanceIntervalBinding:
        Binding<Double> {
        Binding(
            get: {
                draft.distanceIntervalMeters ??
                1_000
            },
            set: {
                draft.distanceIntervalMeters = $0
            }
        )
    }

    private var timeIntervalBinding:
        Binding<Double> {
        Binding(
            get: {
                draft.timeIntervalSeconds ??
                600
            },
            set: {
                draft.timeIntervalSeconds = $0
            }
        )
    }

    private var distanceIntervalLabel: String {
        let meters =
            draft.distanceIntervalMeters ??
            1_000

        if meters >= 1_000 {
            return String(
                format:
                    "Every %.2g km",
                meters / 1_000
            )
        }

        return
            "Every \(Int(meters.rounded())) m"
    }

    private var timeIntervalLabel: String {
        let seconds =
            draft.timeIntervalSeconds ??
            600

        return
            "Every \(max(Int((seconds / 60).rounded()), 1)) min"
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
