import SwiftUI

struct HomeThisWeekCard: View {
    let plan: TrainingPlan?
    let workouts: [WorkoutSummary]
    let streakCount: Int
    let onOpenPlan: () -> Void
    let onOpenWorkout: (UUID) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(spacing: 14) {
                progressRing

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan?.title ?? "Your week")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)

                        if let planStatusText {
                            Text(planStatusText)
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(
                                    ATHLTHTheme.accentDeep
                                )
                                .padding(.horizontal, 7)
                                .frame(height: 22)
                                .background(
                                    ATHLTHTheme.accentSoft,
                                    in: Capsule()
                                )
                                .lineLimit(1)
                        }
                    }

                    Text(weekSummary)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        ATHLTHTheme.accentSoft.opacity(0.78),
                        Color.white.opacity(0.86)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
            )

            weekStrip

            nextUpCard

            summaryRow
        }
        .padding(16)
        .background(
            Color.white.opacity(0.78),
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
                Color.white.opacity(0.90),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: Color.black.opacity(0.035),
            radius: 14,
            y: 6
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ACTIVITY PLAN")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )

                Text(weekRangeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
            }

            Spacer()

            Button {
                onOpenPlan()
            } label: {
                HStack(spacing: 5) {
                    Text("Details")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    ATHLTHTheme.accentDeep
                )
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(
                    ATHLTHTheme.accentSoft,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(
                    ATHLTHTheme.accent.opacity(0.12),
                    lineWidth: 7
                )

            Circle()
                .trim(
                    from: 0,
                    to: max(
                        planProgress,
                        planProgress > 0 ? 0.04 : 0
                    )
                )
                .stroke(
                    ATHLTHTheme.accentDeep,
                    style: StrokeStyle(
                        lineWidth: 7,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(progressValue)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .contentTransition(
                        .numericText()
                    )

                Text(progressCaption)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }
        }
        .frame(width: 66, height: 66)
        .animation(
            .snappy(duration: 0.28),
            value: completedWorkoutCount
        )
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(weekDates, id: \.self) { date in
                dayCell(date)
            }
        }
    }

    @ViewBuilder
    private var nextUpCard: some View {
        if let next = nextPlannedSession {
            Button {
                onOpenWorkout(next.id)
            } label: {
                HStack(spacing: 12) {
                Image(systemName: next.kind.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT UP")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(next.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )
                        .lineLimit(1)

                    Text(nextSessionDetail(next))
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .lineLimit(1)
                }

                Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundStyle(
                            ATHLTHTheme.accentDeep
                        )
                }
                .padding(13)
                .background(
                    Color.primary.opacity(0.025),
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
        } else if plan != nil {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.vitalitySoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEK STATUS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text(
                        plannedWorkoutCount > 0
                            ? "No more planned sessions"
                            : "Flexible week"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                    Text(
                        plannedWorkoutCount > 0
                            ? "Use Quick Train if you want to add something extra."
                            : "Nothing is locked in. Train when it fits."
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }
            .padding(13)
            .background(
                Color.primary.opacity(0.025),
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        } else {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("NO ACTIVE PLAN")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )

                    Text("Build structure when you need it")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            ATHLTHTheme.primaryText
                        )

                    Text(
                        "Your completed workouts still appear here automatically."
                    )
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                }

                Spacer()
            }
            .padding(13)
            .background(
                Color.primary.opacity(0.025),
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
        }
    }

    private var summaryRow: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: 88),
                    spacing: 8
                )
            ],
            spacing: 8
        ) {
            compactMetric(
                value: "\(completedWorkoutCount)",
                title: "Sessions",
                icon: "checkmark.circle.fill",
                tint: ATHLTHTheme.vitality
            )

            compactMetric(
                value:
                    runningDistanceKilometers > 0
                        ? String(
                            format: "%.1f km",
                            runningDistanceKilometers
                        )
                        : "—",
                title: "Run",
                icon: "figure.run",
                tint: .green
            )

            compactMetric(
                value:
                    streakCount > 0
                        ? "\(streakCount)"
                        : "—",
                title: "Streak",
                icon: "flame.fill",
                tint: .orange
            )
        }
    }

    private var weekInterval: DateInterval {
        calendar.dateInterval(
            of: .weekOfYear,
            for: Date()
        ) ??
            DateInterval(
                start: calendar.startOfDay(for: Date()),
                duration: 7 * 86_400
            )
    }

    private var weekDates: [Date] {
        let start = weekInterval.start
        return (0..<7).compactMap {
            calendar.date(
                byAdding: .day,
                value: $0,
                to: start
            )
        }
    }

    private var plannedSessions: [PlannedSession] {
        guard let plan else { return [] }

        return plan.weeks
            .flatMap(\.days)
            .flatMap(\.sessions)
            .filter {
                guard let start = $0.scheduledStart else {
                    return false
                }

                return weekInterval.contains(start)
            }
            .sorted {
                ($0.scheduledStart ?? .distantFuture) <
                    ($1.scheduledStart ?? .distantFuture)
            }
    }

    private var completedWorkouts: [WorkoutSummary] {
        workouts
            .filter {
                weekInterval.contains($0.startDate)
            }
            .sorted {
                $0.startDate < $1.startDate
            }
    }

    private var nextPlannedSession: PlannedSession? {
        let now = Date()

        return plannedSessions.first {
            guard let start = $0.scheduledStart else {
                return false
            }

            return start >= now
        }
    }

    private var completedWorkoutCount: Int {
        completedWorkouts.count
    }

    private var plannedWorkoutCount: Int {
        plannedSessions.count
    }

    private var runningDistanceKilometers: Double {
        completedWorkouts
            .filter {
                $0.activity == .running
            }
            .compactMap(\.distanceMeters)
            .reduce(0, +) / 1_000
    }

    private var planProgress: Double {
        guard plannedWorkoutCount > 0 else {
            return completedWorkoutCount > 0
                ? min(
                    Double(completedWorkoutCount) / 5.0,
                    1
                )
                : 0
        }

        return min(
            Double(completedWorkoutCount) /
                Double(plannedWorkoutCount),
            1
        )
    }

    private var progressValue: String {
        if plannedWorkoutCount > 0 {
            return "\(min(completedWorkoutCount, plannedWorkoutCount))/\(plannedWorkoutCount)"
        }

        return "\(completedWorkoutCount)"
    }

    private var progressCaption: String {
        plannedWorkoutCount > 0
            ? "DONE"
            : "SESSIONS"
    }

    private var planStatusText: String? {
        guard let plan,
              !plan.weeks.isEmpty
        else {
            return nil
        }

        guard let startDate = plan.startDate else {
            return "\(plan.weeks.count) WEEKS"
        }

        let start = calendar.startOfDay(
            for: startDate
        )
        let today = calendar.startOfDay(
            for: Date()
        )
        let days = max(
            calendar.dateComponents(
                [.day],
                from: start,
                to: today
            ).day ?? 0,
            0
        )
        let weekNumber = min(
            days / 7 + 1,
            plan.weeks.count
        )

        return "WEEK \(weekNumber)/\(plan.weeks.count)"
    }

    private var weekSummary: String {
        if plannedWorkoutCount > 0 {
            let remaining = max(
                plannedWorkoutCount - completedWorkoutCount,
                0
            )

            if remaining == 0 {
                return "Your planned training for this week is covered."
            }

            return "\(remaining) planned session\(remaining == 1 ? "" : "s") remaining this week."
        }

        if completedWorkoutCount > 0 {
            return "\(completedWorkoutCount) session\(completedWorkoutCount == 1 ? "" : "s") completed so far."
        }

        return "A clean view of your training rhythm, planned or spontaneous."
    }

    private var weekRangeText: String {
        guard let first = weekDates.first,
              let last = weekDates.last
        else {
            return "This week"
        }

        return first.formatted(
            .dateTime.day().month(.abbreviated)
        ) +
            " – " +
            last.formatted(
                .dateTime.day().month(.abbreviated)
            )
    }

    @ViewBuilder
    private func dayCell(
        _ date: Date
    ) -> some View {
        let actual = completedWorkouts.filter {
            calendar.isDate(
                $0.startDate,
                inSameDayAs: date
            )
        }
        let planned = plannedSessions.filter {
            guard let start = $0.scheduledStart else {
                return false
            }

            return calendar.isDate(
                start,
                inSameDayAs: date
            )
        }
        let isToday = calendar.isDateInToday(date)
        let hasActual = !actual.isEmpty
        let hasPlanned = !planned.isEmpty

        VStack(spacing: 6) {
            Text(
                date.formatted(
                    .dateTime.weekday(.narrow)
                )
            )
            .font(
                .caption2.weight(
                    isToday ? .bold : .semibold
                )
            )
            .foregroundStyle(
                isToday
                    ? ATHLTHTheme.primaryText
                    : ATHLTHTheme.mutedText
            )

            Text(
                date.formatted(
                    .dateTime.day()
                )
            )
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )

            ZStack {
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
                .fill(
                    hasActual
                        ? ATHLTHTheme.vitalitySoft
                        : hasPlanned
                            ? ATHLTHTheme.accentSoft
                            : Color.primary.opacity(0.025)
                )

                if let workout = actual.first {
                    Image(
                        systemName:
                            workout.activity.icon
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.vitality
                    )
                } else if let session = planned.first {
                    Image(
                        systemName:
                            session.kind.systemImage
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme.accentDeep
                    )
                } else {
                    Circle()
                        .fill(
                            Color.primary.opacity(0.10)
                        )
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 38)
            .overlay {
                if isToday {
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                    .stroke(
                        ATHLTHTheme.accentDeep.opacity(0.42),
                        lineWidth: 1
                    )
                }
            }

            Circle()
                .fill(
                    hasActual
                        ? ATHLTHTheme.vitality
                        : hasPlanned
                            ? ATHLTHTheme.accentDeep.opacity(0.55)
                            : Color.clear
                )
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            dayAccessibilityLabel(
                date: date,
                actualCount: actual.count,
                plannedCount: planned.count
            )
        )
    }

    private func nextSessionDetail(
        _ session: PlannedSession
    ) -> String {
        var parts: [String] = []

        if let start = session.scheduledStart {
            if calendar.isDateInToday(start) {
                parts.append(
                    start.formatted(
                        date: .omitted,
                        time: .shortened
                    )
                )
            } else {
                parts.append(
                    start.formatted(
                        .dateTime
                            .weekday(.abbreviated)
                            .hour()
                            .minute()
                    )
                )
            }
        }

        if let minutes = session.durationMinutes {
            parts.append("\(minutes) min")
        }

        if session.routeID != nil {
            parts.append("Route")
        }

        return parts.isEmpty
            ? session.kind.title
            : parts.joined(separator: " · ")
    }

    private func compactMetric(
        value: String,
        title: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 45)
        .background(
            tint.opacity(0.07),
            in: RoundedRectangle(
                cornerRadius: 13,
                style: .continuous
            )
        )
    }

    private func dayAccessibilityLabel(
        date: Date,
        actualCount: Int,
        plannedCount: Int
    ) -> String {
        var parts = [
            date.formatted(
                .dateTime
                    .weekday(.wide)
                    .day()
                    .month(.wide)
            )
        ]

        if actualCount > 0 {
            parts.append(
                "\(actualCount) completed"
            )
        }

        if plannedCount > 0 {
            parts.append(
                "\(plannedCount) planned"
            )
        }

        if actualCount == 0 && plannedCount == 0 {
            parts.append("No activity")
        }

        return parts.joined(separator: ", ")
    }
}

struct HomeGettingStartedPopupView: View {
    @Environment(\.dismiss)
    private var dismiss

    let hasPlan: Bool
    let hasGoal: Bool
    let hasEditedProfile: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text("GETTING STARTED")
                            .font(
                                .caption2
                                    .weight(.bold)
                            )
                            .tracking(2)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .premiumGold
                            )

                        Text(
                            "Make ATHLTH yours"
                        )
                        .font(
                            .system(
                                size: 28,
                                weight: .bold,
                                design: .rounded
                            )
                        )

                        Text(
                            "A few quick steps help ATHLTH tailor training, goals and your profile. You can always change these later."
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            .secondary
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                    .padding(.bottom, 4)

                    gettingStartedDestination(
                        eyebrow: "PROFILE",
                        title: "Edit your profile",
                        detail:
                            "Add your training identity, photo and bio.",
                        icon:
                            "person.crop.circle.badge.pencil",
                        tint:
                            ATHLTHTheme.accent,
                        complete:
                            hasEditedProfile
                    ) {
                        ATHLTHEditProfileView()
                    }

                    gettingStartedDestination(
                        eyebrow:
                            "TRAINING PLAN",
                        title:
                            "Build your training plan",
                        detail:
                            "Organize your week and plan workouts ahead.",
                        icon:
                            "calendar.badge.clock",
                        tint:
                            ATHLTHTheme.accentDeep,
                        complete:
                            hasPlan
                    ) {
                        AdvancedPlannerView()
                    }

                    gettingStartedDestination(
                        eyebrow: "GOALS",
                        title:
                            "Set your first goal",
                        detail:
                            "Set a target and let ATHLTH track your progress.",
                        icon: "target",
                        tint: .green,
                        complete: hasGoal
                    ) {
                        GoalCreationView()
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Continue to ATHLTH")
                            .font(
                                .headline
                            )
                            .frame(
                                maxWidth:
                                    .infinity
                            )
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                    .controlSize(.large)
                    .tint(
                        ATHLTHTheme
                            .accentDeep
                    )
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(
                    maxWidth: 620
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .background(
                ATHLTHPremiumCanvas(
                    accent:
                        ATHLTHTheme
                            .premiumGold
                            .opacity(0.20)
                )
            )
            .navigationTitle(
                "Welcome"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([
            .medium,
            .large
        ])
        .presentationDragIndicator(
            .visible
        )
    }

    private func gettingStartedDestination<
        Destination: View
    >(
        eyebrow: String,
        title: String,
        detail: String,
        icon: String,
        tint: Color,
        complete: Bool,
        @ViewBuilder destination:
            () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            ATHLTHCard {
                HStack(spacing: 14) {
                    Image(
                        systemName: icon
                    )
                    .font(
                        .system(
                            size: 20,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(tint)
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .background(
                        tint.opacity(0.10),
                        in:
                            RoundedRectangle(
                                cornerRadius:
                                    15,
                                style:
                                    .continuous
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(eyebrow)
                            .font(
                                .system(
                                    size: 9,
                                    weight:
                                        .bold
                                )
                            )
                            .tracking(1.2)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )

                        Text(title)
                            .font(.headline)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .primaryText
                            )

                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                            .multilineTextAlignment(
                                .leading
                            )
                    }

                    Spacer()

                    Image(
                        systemName:
                            complete
                                ? "checkmark.circle.fill"
                                : "chevron.right.circle.fill"
                    )
                    .font(
                        .system(
                            size: 21,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        complete
                            ? ATHLTHTheme
                                .vitality
                            : tint
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct HomeGettingStartedCard: View {
    let hasPlan: Bool
    let hasGoal: Bool
    let hasEditedProfile: Bool

    @AppStorage("homeGettingStartedProfileTipDismissed")
    private var profileTipDismissed = false
    @AppStorage("homeGettingStartedPlanTipDismissed")
    private var planTipDismissed = false
    @AppStorage("homeGettingStartedGoalTipDismissed")
    private var goalTipDismissed = false

    private var allComplete: Bool {
        hasEditedProfile && hasPlan && hasGoal
    }

    private var hasVisibleTips: Bool {
        !profileTipDismissed ||
        !planTipDismissed ||
        !goalTipDismissed
    }

    @ViewBuilder
    var body: some View {
        if !allComplete && hasVisibleTips {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Getting started")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Text(
                        "Complete a few essentials to make ATHLTH yours."
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(.horizontal, 4)

                if !profileTipDismissed {
                    gettingStartedTip(
                        eyebrow: "PROFILE",
                        title: "Edit your profile",
                        detail:
                            "Add your training identity, photo and bio.",
                        icon: "person.crop.circle.badge.pencil",
                        tint: ATHLTHTheme.accent,
                        complete: hasEditedProfile,
                        destination: AnyView(
                            ATHLTHEditProfileView()
                        )
                    ) {
                        dismissProfileTip()
                    }
                }

                if !planTipDismissed {
                    gettingStartedTip(
                        eyebrow: "TRAINING PLAN",
                        title: "Build your training plan",
                        detail:
                            "Organize your week and plan your workouts ahead.",
                        icon: "calendar.badge.clock",
                        tint: ATHLTHTheme.accentDeep,
                        complete: hasPlan,
                        destination: AnyView(
                            AdvancedPlannerView()
                        )
                    ) {
                        dismissPlanTip()
                    }
                }

                if !goalTipDismissed {
                    gettingStartedTip(
                        eyebrow: "GOALS",
                        title: "Set your first goal",
                        detail:
                            "Set a target and let ATHLTH track your progress.",
                        icon: "target",
                        tint: .green,
                        complete: hasGoal,
                        destination: AnyView(
                            GoalCreationView()
                        )
                    ) {
                        dismissGoalTip()
                    }
                }
            }
            .transition(
                .opacity.combined(
                    with: .move(edge: .top)
                )
            )
        }
    }

    private func gettingStartedTip(
        eyebrow: String,
        title: String,
        detail: String,
        icon: String,
        tint: Color,
        complete: Bool,
        destination: AnyView,
        onDismiss: @escaping () -> Void
    ) -> some View {
        ATHLTHCard {
            ZStack(alignment: .topTrailing) {
                NavigationLink {
                    destination
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: icon)
                            .font(
                                .system(
                                    size: 20,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(tint)
                            .frame(width: 48, height: 48)
                            .background(
                                tint.opacity(0.10),
                                in: RoundedRectangle(
                                    cornerRadius: 15,
                                    style: .continuous
                                )
                            )

                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(eyebrow)
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .bold
                                    )
                                )
                                .tracking(1.2)
                                .foregroundStyle(
                                    ATHLTHTheme.mutedText
                                )

                            Text(title)
                                .font(.headline)
                                .foregroundStyle(
                                    ATHLTHTheme.primaryText
                                )

                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(
                                    .leading
                                )
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                        }

                        Spacer(minLength: 36)

                        Image(
                            systemName: complete
                                ? "checkmark.circle.fill"
                                : "plus.circle.fill"
                        )
                        .font(
                            .system(
                                size: 22,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            complete
                                ? ATHLTHTheme.vitality
                                : tint
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)

                Button {
                    withAnimation(
                        .easeInOut(duration: 0.20)
                    ) {
                        onDismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(
                            .system(
                                size: 10,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme.mutedText
                        )
                        .frame(width: 26, height: 26)
                        .background(
                            .ultraThinMaterial,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel(
                    ATHLTHLocalization.format(
                    english: "Dismiss %@ tip",
                    norwegian: "Lukk %@-tipset",
                    title
                )
                )
            }
        }
    }

    private func dismissProfileTip() {
        profileTipDismissed = true
    }

    private func dismissPlanTip() {
        planTipDismissed = true
    }

    private func dismissGoalTip() {
        goalTipDismissed = true
    }
}

struct HomeHappeningCard: View {
    let challenges: [ATHLTHChallenge]
    let events: [CommunityEventItem]
    let onOpenCommunity: () -> Void

    private var currentChallenge: ATHLTHChallenge? {
        challenges.first {
            $0.status == .active ||
            $0.status == .upcoming ||
            $0.status == .invited
        }
    }

    private var nextEvent: CommunityEventItem? {
        events
            .filter { $0.event.startsAt >= Date() }
            .sorted { $0.event.startsAt < $1.event.startsAt }
            .first
    }

    var hasContent: Bool {
        currentChallenge != nil || nextEvent != nil
    }

    var body: some View {
        if hasContent {
            ATHLTHCard {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Happening")
                            .font(.title3.weight(.bold))
                        Text("Things that can pull you back into training.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    Spacer()

                    Button("Community") {
                        onOpenCommunity()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .buttonStyle(.plain)
                }

                VStack(spacing: 10) {
                    if let challenge = currentChallenge {
                        NavigationLink {
                            ChallengeDetailView(challengeID: challenge.id)
                        } label: {
                            happeningRow(
                                icon: challenge.sport.systemImage,
                                tint: .orange,
                                eyebrow: challenge.status == .active
                                    ? "ACTIVE CHALLENGE"
                                    : "CHALLENGE",
                                title: challenge.title,
                                detail: challengeDetail(challenge)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let event = nextEvent {
                        NavigationLink {
                            CommunityEventDetailView(eventID: event.id)
                        } label: {
                            happeningRow(
                                icon: event.event.activityType.systemImage,
                                tint: .purple,
                                eyebrow: "NEXT EVENT",
                                title: event.event.title,
                                detail: event.event.startsAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func challengeDetail(_ challenge: ATHLTHChallenge) -> String {
        if let end = challenge.rules.endsAt {
            return "Ends " + end.formatted(
                date: .abbreviated,
                time: .shortened
            )
        }

        return challenge.sport.title
    }

    private func happeningRow(
        icon: String,
        tint: Color,
        eyebrow: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(
                    tint.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(ATHLTHTheme.mutedText)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
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
            in: RoundedRectangle(cornerRadius: 15)
        )
    }
}


// MARK: - Home dashboard v4 compact sections

struct HomeHealthMetricStrip: View {
    let sleepText: String
    let restingHeartRateText: String
    let hrvText: String
    let loadText: String
    let readinessText: String?

    var body: some View {
        HStack(spacing: 8) {
            metric(
                title: "Søvn",
                value: sleepText,
                icon: "moon.fill",
                tint: .indigo,
                bars: [0.26, 0.34, 0.31, 0.45, 0.54, 0.68, 0.84]
            )

            metric(
                title: "Hvilepuls",
                value: restingHeartRateText,
                icon: "heart.fill",
                tint: .pink,
                bars: [0.30, 0.42, 0.36, 0.52, 0.64, 0.49, 0.73]
            )

            metric(
                title: "HRV",
                value: hrvText,
                icon: "waveform.path.ecg",
                tint: .green,
                bars: [0.22, 0.28, 0.38, 0.47, 0.58, 0.72, 0.90]
            )

            metric(
                title: "Belastning",
                value: loadText,
                icon: "chart.bar.fill",
                tint: .blue,
                bars: [0.38, 0.62, 0.45, 0.74, 0.51, 0.66, 0.83],
                badge: readinessText
            )
        }
    }

    private func metric(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        bars: [CGFloat],
        badge: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            if let badge {
                Text(badge)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.vitality)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(
                        ATHLTHTheme.vitalitySoft,
                        in: Capsule()
                    )
                    .lineLimit(1)
            } else {
                Spacer()
                    .frame(height: 18)
            }

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(tint.opacity(0.28 + Double(index) * 0.07))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24 * height)
                }
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.92),
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
                Color.black.opacity(0.045),
                lineWidth: 0.7
            )
        }
        .shadow(
            color: Color.black.opacity(0.025),
            radius: 8,
            y: 3
        )
    }
}

struct HomeWeeklyProgressStrip: View {
    let plan: TrainingPlan?
    let workouts: [WorkoutSummary]
    let onOpenPlan: () -> Void

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Button(action: onOpenPlan) {
                HStack(spacing: 8) {
                    Text("Ukens fremdrift")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Spacer()

                    Text(progressText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ATHLTHTheme.primaryText)

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
            }
            .buttonStyle(.plain)

            ProgressView(value: progress)
                .tint(ATHLTHTheme.vitality)

            HStack(spacing: 6) {
                ForEach(weekDates, id: \.self) { date in
                    day(date)
                }
            }
        }
        .padding(14)
        .background(
            Color.white.opacity(0.90),
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
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
    }

    @ViewBuilder
    private func day(_ date: Date) -> some View {
        let planned = plannedSessions(for: date)
        let actual = workouts.filter {
            calendar.isDate($0.startDate, inSameDayAs: date)
        }
        let hasActual = !actual.isEmpty
        let plannedSession = planned.first
        let isToday = calendar.isDateInToday(date)

        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        hasActual
                            ? ATHLTHTheme.vitality
                            : Color.clear
                    )

                if !hasActual {
                    Circle()
                        .stroke(
                            plannedSession == nil
                                ? Color.secondary.opacity(0.22)
                                : ATHLTHTheme.accentDeep.opacity(0.72),
                            style: StrokeStyle(
                                lineWidth: plannedSession == nil ? 1.2 : 1.8,
                                dash: plannedSession == nil ? [4, 3] : []
                            )
                        )
                }

                if hasActual {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else if let plannedSession {
                    Image(systemName: plannedSession.kind.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                }
            }
            .frame(width: 36, height: 36)
            .overlay {
                if isToday {
                    Circle()
                        .stroke(
                            ATHLTHTheme.accentDeep,
                            lineWidth: 1.4
                        )
                        .padding(-3)
                }
            }

            Text(dayName(date))
                .font(
                    .system(
                        size: 10,
                        weight: isToday ? .bold : .medium
                    )
                )
                .foregroundStyle(
                    isToday
                        ? ATHLTHTheme.primaryText
                        : ATHLTHTheme.mutedText
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var weekInterval: DateInterval {
        calendar.dateInterval(
            of: .weekOfYear,
            for: Date()
        ) ??
            DateInterval(
                start: calendar.startOfDay(for: Date()),
                duration: 7 * 86_400
            )
    }

    private var weekDates: [Date] {
        (0..<7).compactMap {
            calendar.date(
                byAdding: .day,
                value: $0,
                to: weekInterval.start
            )
        }
    }

    private var workoutsThisWeek: [WorkoutSummary] {
        workouts.filter {
            weekInterval.contains($0.startDate)
        }
    }

    private var plannedCount: Int {
        weekDates.reduce(0) {
            $0 + plannedSessions(for: $1).count
        }
    }

    private var completedCount: Int {
        if plannedCount == 0 {
            return workoutsThisWeek.count
        }

        return min(
            workoutsThisWeek.count,
            plannedCount
        )
    }

    private var progress: Double {
        guard plannedCount > 0 else {
            return workoutsThisWeek.isEmpty
                ? 0
                : min(
                    Double(workoutsThisWeek.count) / 5.0,
                    1
                )
        }

        return min(
            Double(completedCount) /
                Double(plannedCount),
            1
        )
    }

    private var progressText: String {
        plannedCount > 0
            ? "\(completedCount) av \(plannedCount) økter"
            : "\(workoutsThisWeek.count) økter"
    }

    private func plannedSessions(
        for date: Date
    ) -> [PlannedSession] {
        guard let plan,
              !plan.weeks.isEmpty
        else {
            return []
        }

        let weekIndex: Int
        if let startDate = plan.startDate {
            let start = calendar.startOfDay(for: startDate)
            let target = calendar.startOfDay(for: date)
            let days = max(
                calendar.dateComponents(
                    [.day],
                    from: start,
                    to: target
                ).day ?? 0,
                0
            )
            weekIndex = min(
                days / 7,
                max(plan.weeks.count - 1, 0)
            )
        } else {
            weekIndex = 0
        }

        guard plan.weeks.indices.contains(weekIndex) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: date)
        let dayIndex = ((weekday + 5) % 7) + 1

        return plan.weeks[weekIndex]
            .days
            .first(where: { $0.dayIndex == dayIndex })?
            .sessions ?? []
    }

    private func dayName(_ date: Date) -> String {
        switch calendar.component(.weekday, from: date) {
        case 2: return "Man"
        case 3: return "Tir"
        case 4: return "Ons"
        case 5: return "Tor"
        case 6: return "Fre"
        case 7: return "Lør"
        default: return "Søn"
        }
    }
}

struct HomeWeeklySummaryCard: View {
    let runningDistanceKilometers: Double
    let durationMinutes: Double
    let strengthSessions: Int
    let sessionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("Denne uken")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Spacer()
            }

            HStack(spacing: 8) {
                weeklyMetric(
                    icon: "figure.run",
                    value:
                        runningDistanceKilometers > 0
                            ? String(
                                format: "%.1f km",
                                locale: Locale.current,
                                runningDistanceKilometers
                            )
                            : "—",
                    caption: "løping"
                )

                weeklyMetric(
                    icon: "stopwatch.fill",
                    value: formattedDuration,
                    caption: "trening"
                )

                weeklyMetric(
                    icon: "dumbbell.fill",
                    value: "\(strengthSessions)",
                    caption: "styrke"
                )

                weeklyMetric(
                    icon: "checkmark.circle.fill",
                    value: "\(sessionCount)",
                    caption: "økter"
                )
            }

            if sessionCount > 0 {
                Label(
                    "Sterk uke så langt – fortsett rytmen.",
                    systemImage: "leaf.fill"
                )
                .font(.caption)
                .foregroundStyle(ATHLTHTheme.mutedText)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.055),
                    Color.white.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
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
            .stroke(
                Color.blue.opacity(0.10),
                lineWidth: 0.7
            )
        }
    }

    private func weeklyMetric(
        icon: String,
        value: String,
        caption: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ATHLTHTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(caption)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(ATHLTHTheme.mutedText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(0.88),
            in: RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    private var formattedDuration: String {
        guard durationMinutes > 0 else {
            return "—"
        }

        let total = Int(durationMinutes.rounded())
        let hours = total / 60
        let minutes = total % 60

        if hours == 0 {
            return "\(minutes) min"
        }

        return "\(hours)t \(minutes)m"
    }
}
