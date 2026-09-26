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
    @State private var weekPendingRemoval: TrainingPlanWeek?

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
                    if let plan = session.activePlan {
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
                            session.addWeekToActivePlan()
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
                                .frame(width: 28, height: 28)
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
                        "\(week.days.reduce(0) { $0 + $1.sessions.count }) total"
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
        let planID = session.activePlan?.id
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
                if let planID {
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
                }

                Divider()

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

        session.removeWeekFromActivePlan(week.id)

        guard let updatedPlan = session.activePlan,
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
                                Text("Zone \(zone)")
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
                                estimatedMaximumHeartRate != nil
                                    ? "ATHLTH estimates zones from your age in Health Profile. Choose Custom BPM if you use lab-tested or manually defined zones."
                                    : "Using the saved BPM range for this zone. Add a date of birth in Health Profile to recalculate estimated zones."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(
                                "A date of birth is needed to estimate zones. Add it in Health Profile or choose Custom BPM."
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

    private var estimatedMaximumHeartRate: Double? {
        guard let dateOfBirth =
                health.personalDetails.dateOfBirth
        else {
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
                estimatedMaximumHeartRate
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
                                "Remove \(workout.title)"
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
                            "\(max(Int((seconds / 60).rounded()), 1)) min",
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
                    : nil
        )

        if existingWorkout != nil,
           let planID {
            session.updateSession(
                workout,
                inPlan: planID
            )
        } else if let dayID {
            session.addSession(
                workout,
                toDay: dayID
            )
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
