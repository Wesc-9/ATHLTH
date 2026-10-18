import Charts
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
            ATHLTHUnifiedCard {
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
        ATHLTHUnifiedCard {
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
            ATHLTHUnifiedCard {
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


// MARK: - Compact Home dashboard

enum HomeHealthMetricKind:
    String,
    CaseIterable,
    Identifiable {

    case sleep
    case respiratoryRate
    case hrv
    case load

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            return "Søvn"
        case .respiratoryRate:
            return "Respirasjon"
        case .hrv:
            return "HRV"
        case .load:
            return "Belastning"
        }
    }

    var icon: String {
        switch self {
        case .sleep:
            return "moon.fill"
        case .respiratoryRate:
            return "lungs.fill"
        case .hrv:
            return "waveform.path.ecg"
        case .load:
            return "chart.bar.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sleep:
            return .indigo
        case .respiratoryRate:
            return .blue
        case .hrv:
            return .red
        case .load:
            return .green
        }
    }

    var unit: String {
        switch self {
        case .sleep:
            return "timer"
        case .respiratoryRate:
            return "bpm"
        case .hrv:
            return "ms"
        case .load:
            return "min"
        }
    }
}

private struct HomeMetricPoint:
    Identifiable {
    let date: Date
    let value: Double?

    var id: Date { date }
}

private enum HomeHealthMetricRange:
    Int,
    CaseIterable,
    Identifiable {
    case week = 7
    case twoWeeks = 14
    case month = 30
    case quarter = 90

    var id: Int { rawValue }

    var compactTitle: String {
        "\(rawValue)d"
    }

    var title: String {
        "\(rawValue) DAGER"
    }
}

struct HomeHealthMetricStrip: View {
    let snapshot: RecoveryTrendSnapshot
    let sleepText: String
    let respiratoryRateText: String
    let hrvText: String
    let loadText: String
    let readinessText: String?

    var body: some View {
        HStack(spacing: 8) {
            metricLink(
                .sleep,
                value: sleepText
            )

            metricLink(
                .respiratoryRate,
                value:
                    respiratoryRateText
            )

            metricLink(
                .hrv,
                value: hrvText
            )

            metricLink(
                .load,
                value: loadText,
                badge:
                    readinessText
            )
        }
    }

    private func metricLink(
        _ kind: HomeHealthMetricKind,
        value: String,
        badge: String? = nil
    ) -> some View {
        NavigationLink {
            HomeHealthMetricDetailView(
                kind: kind,
                snapshot: snapshot
            )
        } label: {
            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                HStack(spacing: 4) {
                    Image(
                        systemName: kind.icon
                    )
                    .font(
                        .system(
                            size: 11.5,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        kind.tint
                    )

                    Text(kind.title)
                        .font(
                            .system(
                                size:
                                    kind ==
                                        .respiratoryRate ||
                                    kind ==
                                        .load
                                        ? 8.6
                                        : 10,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            ATHLTHTheme
                                .primaryText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(
                        minLength: 0
                    )

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .system(
                            size: 8,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                            .opacity(0.72)
                    )
                }

                Text(value)
                    .font(
                        .system(
                            size: 17,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(
                        0.62
                    )

                HStack(spacing: 4) {
                    if let change =
                            changePercent(
                                for: kind
                            ) {
                        Image(
                            systemName:
                                change >= 0
                                    ? "arrow.up"
                                    : "arrow.down"
                        )
                        .font(
                            .system(
                                size: 8,
                                weight: .bold
                            )
                        )

                        Text(
                            changeText(
                                change
                            )
                        )
                        .font(
                            .system(
                                size: 9,
                                weight: .semibold
                            )
                        )
                    } else if let badge {
                        Text(badge)
                            .font(
                                .system(
                                    size: 8.5,
                                    weight:
                                        .semibold
                                )
                            )
                            .lineLimit(1)
                    } else {
                        Text("7 dager")
                            .font(
                                .system(
                                    size: 8.5,
                                    weight:
                                        .medium
                                )
                            )
                    }
                }
                .foregroundStyle(
                    changeTint(
                        for: kind
                    )
                )
                .frame(height: 13)

                HomeMetricMiniBars(
                    values:
                        points(
                            for: kind
                        )
                        .suffix(7)
                        .map(\.value),
                    tint: kind.tint,
                    zeroIsEmpty:
                        kind == .load
                )
                .frame(height: 24)
            }
            .padding(
                .horizontal,
                9
            )
            .padding(
                .vertical,
                10
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background(
                Color.white.opacity(
                    0.92
                ),
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
                    Color.black.opacity(
                        0.045
                    ),
                    lineWidth: 0.7
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func points(
        for kind: HomeHealthMetricKind
    ) -> [HomeMetricPoint] {
        snapshot.days.map { day in
            let value: Double?

            switch kind {
            case .sleep:
                value =
                    day.sleepDuration.map {
                        $0 / 3_600
                    }
            case .respiratoryRate:
                value =
                    day.respiratoryRate
            case .hrv:
                value =
                    day.hrvMilliseconds
            case .load:
                value =
                    day.trainingMinutes
            }

            return HomeMetricPoint(
                date: day.date,
                value: value
            )
        }
    }

    private func changePercent(
        for kind: HomeHealthMetricKind
    ) -> Double? {
        let values =
            points(for: kind)
                .suffix(14)
                .map(\.value)

        guard values.count >= 8 else {
            return nil
        }

        let recent =
            Array(
                values.suffix(7)
            )
            .compactMap { $0 }
        let previous =
            Array(
                values.dropLast(
                    min(7, values.count)
                )
                .suffix(7)
            )
            .compactMap { $0 }

        guard !recent.isEmpty,
              !previous.isEmpty
        else {
            return nil
        }

        let currentAverage =
            recent.reduce(0, +) /
            Double(recent.count)
        let previousAverage =
            previous.reduce(0, +) /
            Double(previous.count)

        guard previousAverage > 0 else {
            return nil
        }

        return
            ((currentAverage -
                previousAverage) /
                previousAverage) *
            100
    }

    private func changeTint(
        for kind: HomeHealthMetricKind
    ) -> Color {
        guard let change =
                changePercent(
                    for: kind
                )
        else {
            return ATHLTHTheme
                .mutedText
        }

        switch kind {
        case .respiratoryRate:
            return ATHLTHTheme.accentDeep
        case .load:
            return ATHLTHTheme
                .accentDeep
        case .sleep, .hrv:
            return change >= 0
                ? ATHLTHTheme.vitality
                : .orange
        }
    }

    private func changeText(
        _ value: Double
    ) -> String {
        let prefix =
            value > 0 ? "+" : ""
        return
            "\(prefix)\(Int(value.rounded())) %"
    }
}

/// Stateless calculations used by Home's tiny recovery charts. SwiftUI may
/// render chart layout on AsyncRenderer, so these helpers must not inherit
/// View / MainActor isolation or access an observable store.
enum HomeMetricMiniBarMath {
    nonisolated static func roundedScaleMaximum(_ value: Double) -> Double {
        guard value > 0 else { return 1 }

        let magnitude = pow(10, floor(log10(value)))
        let normalized = value / magnitude
        let rounded: Double
        switch normalized {
        case ...1: rounded = 1
        case ...2: rounded = 2
        case ...4: rounded = 4
        case ...5: rounded = 5
        default: rounded = 10
        }
        return max(rounded * magnitude, value)
    }

    nonisolated static func barHeight(
        value: Double?,
        maximum: Double,
        availableHeight: CGFloat,
        zeroIsEmpty: Bool
    ) -> CGFloat {
        guard let value, value.isFinite, value >= 0 else { return 4 }
        if zeroIsEmpty && value <= 0 { return 0 }
        return max(4, availableHeight * CGFloat(min(value / maximum, 1)))
    }
}

private struct HomeMetricMiniBars: View {
    let values: [Double?]
    let tint: Color
    let zeroIsEmpty: Bool

    var body: some View {
        // Snapshot everything before entering SwiftUI's asynchronous geometry
        // renderer. This closure must not call MainActor-isolated view methods.
        let resolved: [Double?] = values.isEmpty
            ? Array(repeating: nil, count: 7)
            : values
        let valid = resolved.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        let rawMaximum = valid.max() ?? 0
        let maximum = zeroIsEmpty
            ? HomeMetricMiniBarMath.roundedScaleMaximum(rawMaximum)
            : max(rawMaximum, 0.001)
        let color = tint
        let treatsZeroAsEmpty = zeroIsEmpty

        return GeometryReader { @Sendable proxy in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(resolved.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(
                            value == nil
                                ? color.opacity(0.10)
                                : color.opacity(0.66)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(
                            height: HomeMetricMiniBarMath.barHeight(
                                value: value,
                                maximum: maximum,
                                availableHeight: proxy.size.height,
                                zeroIsEmpty: treatsZeroAsEmpty
                            )
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct HomeHealthMetricDetailView:
    View {
    @EnvironmentObject private var health:
        HealthKitManager

    let kind: HomeHealthMetricKind
    let snapshot:
        RecoveryTrendSnapshot

    @State private var selectedRange:
        HomeHealthMetricRange = .week
    @State private var loadedSnapshot:
        RecoveryTrendSnapshot?
    @State private var isLoadingRange = false

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 18
            ) {
                HStack(spacing: 12) {
                    Image(
                        systemName:
                            kind.icon
                    )
                    .font(
                        .system(
                            size: 20,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        kind.tint
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )
                    .background(
                        kind.tint.opacity(
                            0.10
                        ),
                        in:
                            RoundedRectangle(
                                cornerRadius: 15,
                                style:
                                    .continuous
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(kind.title)
                            .font(
                                .title2
                                    .weight(
                                        .bold
                                    )
                            )

                        Text(
                            detailSubtitle
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                    }

                    Spacer()
                }

                ATHLTHUnifiedCard {
                    HStack(
                        alignment: .top
                    ) {
                        VStack(
                            alignment:
                                .leading,
                            spacing: 3
                        ) {
                            Text("Siste verdi")
                                .font(
                                    .caption
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .mutedText
                                )

                            Text(latestValueText)
                                .font(
                                    .system(
                                        size: 28,
                                        weight: .bold,
                                        design:
                                            .rounded
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                        }

                        Spacer(minLength: 16)

                        VStack(
                            alignment: .trailing,
                            spacing: 3
                        ) {
                            Text(selectedRange.title)
                                .font(
                                    .system(
                                        size: 9,
                                        weight: .bold
                                    )
                                )
                                .tracking(1.1)
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .accentDeep
                                )

                            Text(
                                ATHLTHLocalization.choose(
                                    english: "Average",
                                    norwegian: "Gjennomsnitt"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(
                                ATHLTHTheme
                                    .mutedText
                            )

                            Text(averageValueText)
                                .font(
                                    .system(
                                        size: 20,
                                        weight: .semibold,
                                        design:
                                            .rounded
                                    )
                                )
                                .foregroundStyle(
                                    ATHLTHTheme
                                        .primaryText
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }

                    Picker(
                        "Periode",
                        selection:
                            $selectedRange
                    ) {
                        ForEach(
                            HomeHealthMetricRange
                                .allCases
                        ) { range in
                            Text(
                                range.compactTitle
                            )
                            .tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 12)

                    if isLoadingRange {
                        ProgressView(
                            "Henter \(selectedRange.rawValue) dager…"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            ATHLTHTheme
                                .mutedText
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .padding(.top, 6)
                    }

                    detailChart
                        .frame(height: 210)
                        .padding(.top, 10)
                }

                ATHLTHUnifiedCard {
                    Text(
                        ATHLTHLocalization.choose(
                            english: "About the data",
                            norwegian: "Om dataene"
                        )
                    )
                    .font(
                        .headline
                            .weight(
                                .bold
                            )
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 14
                    ) {
                        metricInfoRow(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "What it is",
                                    norwegian: "Hva det er"
                                ),
                            icon: "info.circle",
                            text: whatItIs
                        )

                        Divider()
                            .opacity(0.55)

                        metricInfoRow(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "How it is measured",
                                    norwegian: "Hvordan det måles"
                                ),
                            icon: "applewatch",
                            text: howItIsMeasured
                        )

                        Divider()
                            .opacity(0.55)

                        metricInfoRow(
                            title:
                                ATHLTHLocalization.choose(
                                    english: "How to use it in training",
                                    norwegian: "Hvordan bruke det i trening"
                                ),
                            icon: "figure.run",
                            text: trainingUse
                        )
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(
            ATHLTHTheme.canvasTop
                .ignoresSafeArea()
        )
        .navigationTitle(
            kind.title
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        .task(id: selectedRange) {
            await loadSelectedRange()
        }
    }

    @ViewBuilder
    private var detailChart:
        some View {
        let data = points

        Chart(data) { point in
            if let value =
                    point.value {
                if kind == .load {
                    BarMark(
                        x: .value(
                            "Dag",
                            point.date
                        ),
                        y: .value(
                            "Verdi",
                            value
                        )
                    )
                    .foregroundStyle(
                        kind.tint
                    )
                    .cornerRadius(4)
                } else {
                    LineMark(
                        x: .value(
                            "Dag",
                            point.date
                        ),
                        y: .value(
                            "Verdi",
                            value
                        )
                    )
                    .foregroundStyle(
                        kind.tint
                    )
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 2.2,
                            lineCap: .round,
                            lineJoin:
                                .round
                        )
                    )
                    .interpolationMethod(
                        .catmullRom
                    )

                    PointMark(
                        x: .value(
                            "Dag",
                            point.date
                        ),
                        y: .value(
                            "Verdi",
                            value
                        )
                    )
                    .foregroundStyle(
                        kind.tint
                    )
                }
            }
        }
        .chartXAxis {
            AxisMarks(
                values:
                    .automatic(
                        desiredCount: 5
                    )
            ) {
                AxisValueLabel(
                    format:
                        .dateTime
                            .day()
                )
            }
        }
        .chartYAxis {
            AxisMarks(
                position: .leading
            )
        }
    }

    private var activeSnapshot:
        RecoveryTrendSnapshot {
        if let loadedSnapshot,
           loadedSnapshot.days.count >=
            selectedRange.rawValue {
            return loadedSnapshot
        }

        return snapshot
    }

    private var points:
        [HomeMetricPoint] {
        activeSnapshot.days
            .suffix(selectedRange.rawValue)
            .map { day in
                let value: Double?

                switch kind {
                case .sleep:
                    value =
                        day.sleepDuration.map {
                            $0 / 3_600
                        }
                case .respiratoryRate:
                    value =
                        day.restingHeartRate
                case .hrv:
                    value =
                        day.hrvMilliseconds
                case .load:
                    value =
                        day.trainingMinutes
                }

                return HomeMetricPoint(
                    date: day.date,
                    value: value
                )
            }
    }

    @MainActor
    private func loadSelectedRange()
        async {
        let requestedDays =
            selectedRange.rawValue

        if requestedDays <=
            snapshot.days.count {
            isLoadingRange = false
            return
        }

        if let loadedSnapshot,
           loadedSnapshot.days.count >=
            requestedDays {
            isLoadingRange = false
            return
        }

        isLoadingRange = true

        let fetched =
            await health
                .recoveryTrendSnapshot(
                    days: requestedDays
                )

        guard !Task.isCancelled else {
            return
        }

        loadedSnapshot = fetched
        isLoadingRange = false
    }

    private var latestValueText:
        String {
        guard let value =
                points
                    .reversed()
                    .compactMap(
                        \.value
                    )
                    .first
        else {
            return "—"
        }

        return formattedMetricValue(value)
    }

    private var averageValueText:
        String {
        let values =
            points
                .compactMap(\.value)
                .filter {
                    $0.isFinite &&
                        $0 >= 0
                }

        guard !values.isEmpty else {
            return "—"
        }

        let average =
            values.reduce(0, +) /
                Double(values.count)

        return formattedMetricValue(
            average
        )
    }

    private func formattedMetricValue(
        _ value: Double
    ) -> String {
        switch kind {
        case .sleep:
            let totalMinutes =
                Int(
                    (value * 60)
                        .rounded()
                )
            return
                "\(totalMinutes / 60) t \(totalMinutes % 60) min"
        case .respiratoryRate:
            return
                "\(Int(value.rounded())) bpm"
        case .hrv:
            return
                "\(Int(value.rounded())) ms"
        case .load:
            return
                "\(Int(value.rounded())) min"
        }
    }

    private var detailSubtitle:
        String {
        switch kind {
        case .sleep:
            return
                "Registrert søvn fra Apple Health."
        case .respiratoryRate:
            return
                "Daglig respirasjonsfrekvens fra Apple Health."
        case .hrv:
            return
                "Daglig HRV fra Apple Health."
        case .load:
            return
                "Treningsminutter per dag."
        }
    }

    private func metricInfoRow(
        title: String,
        icon: String,
        text: String
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(kind.tint)
                .frame(
                    width: 30,
                    height: 30
                )
                .background(
                    kind.tint.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )

                Text(text)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme.mutedText
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
        }
    }

    private var whatItIs: String {
        switch kind {
        case .sleep:
            return ATHLTHLocalization.choose(
                english:
                    "Sleep duration is the amount of sleep recorded for the night. It is most useful as a trend together with how rested you feel.",
                norwegian:
                    "Søvn viser hvor mye søvn som er registrert gjennom natten. Det er mest nyttig som en trend sammen med hvordan du faktisk føler deg."
            )
        case .respiratoryRate:
            return ATHLTHLocalization.choose(
                english:
                    "Respiratory rate is the number of breaths you take per minute. Your personal baseline and longer-term trend are more useful than comparison with other people.",
                norwegian:
                    "Respirasjonsfrekvens er antall pust du tar per minutt. Din egen grunnlinje og utviklingen over tid er mer nyttig enn å sammenligne tallet med andre."
            )
        case .hrv:
            return ATHLTHLocalization.choose(
                english:
                    "HRV is the variation in time between consecutive heartbeats. It reflects autonomic nervous-system activity and naturally varies from day to day.",
                norwegian:
                    "HRV er variasjonen i tid mellom påfølgende hjerteslag. Den gjenspeiler aktivitet i det autonome nervesystemet og varierer naturlig fra dag til dag."
            )
        case .load:
            return ATHLTHLocalization.choose(
                english:
                    "Training load summarizes how much recorded training you have accumulated. This view currently uses training duration as its main input.",
                norwegian:
                    "Belastning oppsummerer hvor mye registrert trening du har samlet. Denne visningen bruker foreløpig treningsvarighet som hovedgrunnlag."
            )
        }
    }

    private var howItIsMeasured: String {
        switch kind {
        case .sleep:
            return ATHLTHLocalization.choose(
                english:
                    "ATHLTH reads compatible sleep records from Apple Health. Apple Watch and other supported sources can contribute these records. Missing nights are left empty rather than estimated.",
                norwegian:
                    "ATHLTH leser kompatible søvnregistreringer fra Apple Health. Apple Watch og andre støttede kilder kan bidra med data. Netter uten data blir stående tomme i stedet for å bli estimert."
            )
        case .respiratoryRate:
            return ATHLTHLocalization.choose(
                english:
                    "ATHLTH reads respiratory-rate samples from Apple Health. Compatible Apple Watch models can estimate breathing rate during suitable periods, especially during sleep.",
                norwegian:
                    "ATHLTH leser respirasjonsfrekvens fra Apple Health. Kompatible Apple Watch-modeller kan estimere pustefrekvens i egnede perioder, særlig under søvn."
            )
        case .hrv:
            return ATHLTHLocalization.choose(
                english:
                    "ATHLTH reads HRV samples from Apple Health, reported in milliseconds. Apple Watch can record HRV during suitable periods, including when you are still or during supported sessions.",
                norwegian:
                    "ATHLTH leser HRV-målinger fra Apple Health, oppgitt i millisekunder. Apple Watch kan registrere HRV i egnede perioder, blant annet når du er i ro eller under støttede målinger."
            )
        case .load:
            return ATHLTHLocalization.choose(
                english:
                    "ATHLTH uses recorded workouts and their duration. A minute of easy walking and a minute of hard intervals are therefore not treated as physiologically identical; the graph is a duration-based overview.",
                norwegian:
                    "ATHLTH bruker registrerte treningsøkter og varigheten deres. Ett minutt rolig gange og ett minutt harde intervaller regnes derfor ikke som fysiologisk identiske; grafen er en varighetsbasert oversikt."
            )
        }
    }

    private var trainingUse: String {
        switch kind {
        case .sleep:
            return ATHLTHLocalization.choose(
                english:
                    "Use several nights together with energy, soreness and your planned session. Repeatedly short sleep can be a reason to reduce volume or intensity, while one short night does not automatically require a change.",
                norwegian:
                    "Se flere netter i sammenheng med energi, muskelømhet og den planlagte økten. Gjentatt kort søvn kan være et signal om å redusere volum eller intensitet, mens én kort natt ikke automatisk betyr at planen må endres."
            )
        case .respiratoryRate:
            return ATHLTHLocalization.choose(
                english:
                    "Compare the trend with your own recent baseline. A persistent change together with poor sleep, fatigue or feeling unwell can be a reason to keep training flexible. Do not use one respiratory-rate reading alone to set training intensity.",
                norwegian:
                    "Sammenlign utviklingen med din egen nyere grunnlinje. En vedvarende endring sammen med dårlig søvn, tretthet eller sykdomsfølelse kan være en grunn til å holde treningen fleksibel. Ikke bruk én respirasjonsmåling alene til å styre intensiteten."
            )
        case .hrv:
            return ATHLTHLocalization.choose(
                english:
                    "Look for a multi-day pattern relative to your own baseline. A sustained drop together with other recovery signals can support reducing intensity or volume. A single low HRV value is common and is not a diagnosis.",
                norwegian:
                    "Se etter utviklingen over flere dager mot din egen grunnlinje. Et vedvarende fall sammen med andre restitusjonssignaler kan støtte lavere intensitet eller volum. En enkelt lav HRV-måling er vanlig og er ikke en diagnose."
            )
        case .load:
            return ATHLTHLocalization.choose(
                english:
                    "Use the trend to see whether recent training volume is rising, stable or falling. Combine it with workout intensity, soreness and recovery before changing your plan.",
                norwegian:
                    "Bruk utviklingen til å se om treningsmengden nylig øker, er stabil eller faller. Se den sammen med intensitet, muskelømhet og restitusjon før du endrer planen."
            )
        }
    }
}

/// Pure calendar calculations shared by Home's week pager and tests.
/// Plan weeks start on the configured plan start, not necessarily Monday.
enum HomeWeeklyProgressCalendar {
    /// Only use a plan ID when this exact workout belongs to that plan.
    /// Standalone calendar workouts intentionally have no plan parent.
    static func containingPlanID(
        for workout: PlannedSession,
        in plan: TrainingPlan?
    ) -> UUID? {
        guard let plan else { return nil }
        let containsWorkout = plan.weeks.contains { week in
            week.days.contains { day in
                day.sessions.contains { $0.id == workout.id }
            }
        }
        return containsWorkout ? plan.id : nil
    }

    // The Home shortcut must never offer scheduling on a previous day.
    // Compare calendar days rather than clock times, so today is allowed all day.
    static func canScheduleStandalone(
        on date: Date,
        asOf now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: date) >=
            calendar.startOfDay(for: now)
    }

    static func weekInterval(
        offset: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> DateInterval {
        let currentStart = calendar.dateInterval(
            of: .weekOfYear, for: referenceDate
        )?.start ?? calendar.startOfDay(for: referenceDate)
        let start = calendar.date(
            byAdding: .weekOfYear,
            value: offset,
            to: currentStart
        ) ?? currentStart
        let end = calendar.date(
            byAdding: .weekOfYear,
            value: 1,
            to: start
        ) ?? start.addingTimeInterval(7 * 86_400)
        return DateInterval(start: start, end: end)
    }

    static func planPosition(
        for date: Date,
        startDate: Date,
        calendar: Calendar
    ) -> (weekIndex: Int, dayIndex: Int)? {
        let first = calendar.startOfDay(for: startDate)
        let selected = calendar.startOfDay(for: date)
        let elapsed = calendar.dateComponents(
            [.day], from: first, to: selected
        ).day ?? -1
        guard elapsed >= 0 else { return nil }
        return (weekIndex: elapsed / 7, dayIndex: elapsed % 7 + 1)
    }
}

private struct HomeWeeklyProgressDaySelection:
    Identifiable {
    var id: Date { date }

    let date: Date
    let planned: [PlannedSession]
    let communityEvents:
        [HomeScheduledCommunityEvent]
    let actual: [WorkoutSummary]
    let completedPlannedIDs: Set<UUID>
    let completedCommunityEventIDs:
        Set<String>
}

struct HomeScheduledCommunityEvent:
    Identifiable,
    Hashable
{
    let id: String
    let title: String
    let startsAt: Date
    let activityType: String
    let systemImage: String
    let detail: String
}

struct HomeWeeklyProgressStrip:
    View {
    @EnvironmentObject private var session:
        AppSessionStore
    @EnvironmentObject private var strength:
        StrengthWorkoutStore

    let plan: TrainingPlan?
    let workouts: [WorkoutSummary]
    let events:
        [HomeScheduledCommunityEvent]

    @State private var weekOffset = 0
    @State private var selectedDay:
        HomeWeeklyProgressDaySelection?
    @State private var daySheetDetent: PresentationDetent = .fraction(0.82)

    private var calendar:
        Calendar {
        var value =
            Calendar.current
        value.firstWeekday = 2
        return value
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            HStack(spacing: 7) {
                Text("Ukens fremdrift")
                    .font(
                        .system(
                            size: 13,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Text(
                    "Uke \(calendar.component(.weekOfYear, from: visibleWeekInterval.start))"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ATHLTHTheme.mutedText)
                .lineLimit(1)

                Spacer(minLength: 2)

                if weekOffset != 0 {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            weekOffset = 0
                        }
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .accessibilityLabel(
                        ATHLTHLocalization.choose(
                            english: "Back to current week",
                            norwegian: "Tilbake til denne uken"
                        )
                    )
                }

                Text(progressText)
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
            }

            ProgressView(
                value: progress
            )
            .tint(
                ATHLTHTheme.vitality
            )
            .scaleEffect(
                x: 1,
                y: 0.62,
                anchor: .center
            )

            HStack(spacing: 3) {
                weekNavigationButton(
                    systemImage: "chevron.left"
                ) {
                    withAnimation(.snappy(duration: 0.22)) {
                        weekOffset -= 1
                    }
                }

                ForEach(
                    visibleWeekDates,
                    id: \.self
                ) { date in
                    dayButton(date)
                }

                weekNavigationButton(
                    systemImage: "chevron.right"
                ) {
                    withAnimation(
                        .snappy(
                            duration: 0.22
                        )
                    ) {
                        weekOffset += 1
                    }
                }
            }

            Divider()
                .opacity(0.30)
                .padding(.top, 1)

            compactWeekMetrics
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            Color.white.opacity(0.90),
            in: RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
            .stroke(
                Color.black.opacity(0.04),
                lineWidth: 0.7
            )
        }
        .sheet(item: $selectedDay) {
            selection in
            HomeWeeklyProgressDaySheet(
                selection: selection,
                plan: plan,
                onOpenWorkout: {
                    daySheetDetent = .large
                }
            )
            .presentationDetents(
                [.fraction(0.82), .large],
                selection: $daySheetDetent
            )
            .presentationDragIndicator(
                .visible
            )
            .presentationCornerRadius(
                28
            )
        }
    }

    @ViewBuilder
    private func dayButton(
        _ date: Date
    ) -> some View {
        let planned =
            plannedSessions(
                for: date
            )
        let actual =
            workoutsForDay(
                date
            )
        let scheduledCommunityEvents =
            communityEventsForDay(
                date
            )
        let completedIDs =
            completedPlanSessionIDs(
                date: date,
                planned: planned
            )
        let completedCommunityIDs =
            completedCommunityEventIDs(
                date: date,
                events:
                    scheduledCommunityEvents
            )

        Button {
            daySheetDetent = .fraction(0.82)
            selectedDay =
                HomeWeeklyProgressDaySelection(
                    date: date,
                    planned: planned,
                    communityEvents:
                        scheduledCommunityEvents,
                    actual: actual,
                    completedPlannedIDs:
                        completedIDs,
                    completedCommunityEventIDs:
                        completedCommunityIDs
                )
        } label: {
            day(
                date,
                planned: planned,
                communityEvents:
                    scheduledCommunityEvents,
                actual: actual,
                completedIDs:
                    completedIDs,
                completedCommunityIDs:
                    completedCommunityIDs
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            ATHLTHLocalization.choose(
                english:
                    "Show workouts for this day",
                norwegian:
                    "Vis økter for denne dagen"
            )
        )
    }

    private func day(
        _ date: Date,
        planned: [PlannedSession],
        communityEvents:
            [HomeScheduledCommunityEvent],
        actual: [WorkoutSummary],
        completedIDs: Set<UUID>,
        completedCommunityIDs:
            Set<String>
    ) -> some View {
        let plannedSession =
            planned.first {
                !completedIDs
                    .contains($0.id)
            } ??
            planned.first
        let plannedCommunityEvent =
            communityEvents.first {
                !completedCommunityIDs
                    .contains($0.id)
            } ??
            communityEvents.first
        let scheduledCount =
            planned.count +
            communityEvents.count
        let completedScheduledCount =
            completedIDs.count +
            completedCommunityIDs.count
        let allScheduledCompleted =
            scheduledCount > 0 &&
            completedScheduledCount >=
                scheduledCount
        let hasUnplannedActual =
            scheduledCount == 0 &&
            !actual.isEmpty
        let isCompleted =
            allScheduledCompleted ||
            hasUnplannedActual
        let isToday =
            calendar.isDateInToday(
                date
            )

        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(
                        isCompleted
                            ? ATHLTHTheme
                                .vitality
                            : Color.clear
                    )

                if !isCompleted {
                    Circle()
                        .stroke(
                            plannedSession ==
                                nil &&
                            plannedCommunityEvent ==
                                nil
                                ? Color
                                    .secondary
                                    .opacity(
                                        0.18
                                    )
                                : ATHLTHTheme
                                    .accentDeep
                                    .opacity(
                                        0.72
                                    ),
                            style:
                                StrokeStyle(
                                    lineWidth:
                                        plannedSession ==
                                        nil &&
                                    plannedCommunityEvent ==
                                        nil
                                            ? 1
                                            : 1.5,
                                    dash:
                                        plannedSession ==
                                        nil &&
                                    plannedCommunityEvent ==
                                        nil
                                            ? [
                                                3,
                                                3
                                            ]
                                            : []
                                )
                        )
                }

                if isCompleted {
                    Image(
                        systemName:
                            "checkmark"
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .white
                    )
                } else if let plannedSession {
                    Image(
                        systemName:
                            plannedSession
                                .kind
                                .systemImage
                    )
                    .font(
                        .system(
                            size: 10,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                } else if let plannedCommunityEvent {
                    Image(
                        systemName:
                            plannedCommunityEvent
                                .systemImage
                    )
                    .font(
                        .system(
                            size: 10,
                            weight:
                                .semibold
                        )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .accentDeep
                    )
                }
            }
            .frame(
                width: 24,
                height: 24
            )
            .overlay {
                if isToday {
                    Circle()
                        .stroke(
                            ATHLTHTheme
                                .accentDeep,
                            lineWidth: 1.1
                        )
                        .padding(-2)
                }
            }

            Text(
                dayName(date)
            )
            .font(
                .system(
                    size: 8.5,
                    weight:
                        isToday
                            ? .bold
                            : .medium
                )
            )
            .foregroundStyle(
                isToday
                    ? ATHLTHTheme
                        .primaryText
                    : ATHLTHTheme
                        .mutedText
            )
        }
        .frame(
            maxWidth: .infinity
        )
        .contentShape(
            Rectangle()
        )
    }

    private func weekNavigationButton(
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(
            action: action
        ) {
            Image(
                systemName:
                    systemImage
            )
            .font(
                .system(
                    size: 10,
                    weight: .bold
                )
            )
            .foregroundStyle(
                enabled
                    ? ATHLTHTheme
                        .primaryText
                    : ATHLTHTheme
                        .mutedText
                        .opacity(0.35)
            )
            .frame(
                width: 27,
                height: 27
            )
            .background(
                Color.white.opacity(
                    enabled
                        ? 0.80
                        : 0.40
                ),
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        Color.black.opacity(
                            0.045
                        ),
                        lineWidth: 0.7
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            systemImage ==
                "chevron.right"
                ? ATHLTHLocalization.choose(
                    english:
                        "Next week",
                    norwegian:
                        "Neste uke"
                )
                : ATHLTHLocalization.choose(
                    english:
                        "Previous week",
                    norwegian:
                        "Forrige uke"
                )
        )
    }

    private var currentWeekInterval:
        DateInterval {
        calendar.dateInterval(
            of: .weekOfYear,
            for: Date()
        ) ??
            DateInterval(
                start:
                    calendar
                        .startOfDay(
                            for: Date()
                        ),
                duration:
                    7 * 86_400
            )
    }

    private var visibleWeekInterval:
        DateInterval {
        HomeWeeklyProgressCalendar.weekInterval(
            offset: weekOffset,
            referenceDate: Date(),
            calendar: calendar
        )
    }

    private var visibleWeekDates:
        [Date] {
        (0..<7).compactMap {
            calendar.date(
                byAdding: .day,
                value: $0,
                to:
                    visibleWeekInterval
                        .start
            )
        }
    }

    private var visibleWorkouts:
        [WorkoutSummary] {
        workouts.filter {
            visibleWeekInterval
                .contains(
                    $0.startDate
                )
        }
    }

    private var compactWeekMetrics:
        some View {
        HStack(
            spacing: visibleWeekOtherWorkouts.isEmpty ? 4 : 2
        ) {
            compactWeekMetric(
                icon: "figure.run",
                value:
                    visibleWeekRunningDistanceKilometers >
                        0
                        ? String(
                            format: "%.1f km",
                            locale:
                                Locale.current,
                            visibleWeekRunningDistanceKilometers
                        )
                        : "—",
                accessibilityTitle:
                    ATHLTHLocalization.choose(
                        english:
                            "Running distance",
                        norwegian:
                            "Løpedistanse"
                    )
            )

            compactWeekMetric(
                icon: "stopwatch.fill",
                value:
                    visibleWeekDurationText,
                accessibilityTitle:
                    ATHLTHLocalization.choose(
                        english:
                            "Training time",
                        norwegian:
                            "Treningstid"
                    )
            )

            compactWeekMetric(
                icon: "dumbbell.fill",
                value:
                    "\(visibleWeekStrengthSessions)",
                accessibilityTitle:
                    ATHLTHLocalization.choose(
                        english:
                            "Strength workouts",
                        norwegian:
                            "Styrkeøkter"
                    )
            )

            compactWeekMetric(
                icon: "figure.walk",
                value:
                    "\(visibleWeekRunningWalkingSessions)",
                accessibilityTitle:
                    ATHLTHLocalization.choose(
                        english:
                            "Running and walking workouts",
                        norwegian:
                            "Løpe- og gåøkter"
                    )
            )

            // Keep the regular four metrics unchanged unless the selected
            // week contains a different workout activity.
            if !visibleWeekOtherWorkouts.isEmpty {
                compactWeekMetric(
                    icon: visibleWeekOtherWorkoutIcon,
                    value:
                        "\(visibleWeekOtherWorkouts.count)",
                    accessibilityTitle:
                        visibleWeekOtherWorkoutTitle
                )
            }
        }
    }

    private func compactWeekMetric(
        icon: String,
        value: String,
        accessibilityTitle: String
    ) -> some View {
        let hasFifthMetric =
            !visibleWeekOtherWorkouts.isEmpty

        return HStack(
            spacing: hasFifthMetric ? 2 : 4
        ) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: hasFifthMetric ? 8 : 9,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .accentDeep
                )

            Text(value)
                .font(
                    .system(
                        size: hasFifthMetric ? 9.5 : 10.5,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(
            maxWidth: .infinity
        )
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            accessibilityTitle
        )
        .accessibilityValue(value)
    }

    private var visibleWeekRunningDistanceKilometers:
        Double {
        visibleWorkouts
            .filter {
                $0.activity == .running
            }
            .compactMap(
                \.distanceMeters
            )
            .reduce(0, +) /
            1_000
    }

    private var visibleWeekDurationMinutes:
        Double {
        visibleWorkouts.reduce(0) {
            $0 +
                max(
                    $1.duration / 60,
                    0
                )
        }
    }

    private var visibleWeekStrengthSessions:
        Int {
        visibleWorkouts
            .filter {
                $0.activity == .strength
            }
            .count
    }

    private var visibleWeekRunningWalkingSessions:
        Int {
        visibleWorkouts
            .filter {
                $0.activity == .running ||
                    $0.activity == .walking
            }
            .count
    }

    private var visibleWeekOtherWorkouts:
        [WorkoutSummary] {
        visibleWorkouts.filter {
            $0.activity != .running &&
                $0.activity != .walking &&
                $0.activity != .strength
        }
    }

    // Display the relevant sport when all extra sessions share one
    // activity. Different extra sports are grouped in the fifth slot.
    private var visibleWeekOtherActivity:
        WorkoutActivity? {
        let activities =
            Set(visibleWeekOtherWorkouts.map(\.activity))
        guard activities.count == 1 else {
            return nil
        }
        return activities.first
    }

    private var visibleWeekOtherWorkoutIcon:
        String {
        visibleWeekOtherActivity?.icon ??
            "figure.mixed.cardio"
    }

    private var visibleWeekOtherWorkoutTitle:
        String {
        guard let activity = visibleWeekOtherActivity
        else {
            return ATHLTHLocalization.choose(
                english: "Other workouts",
                norwegian: "Andre økter"
            )
        }

        switch activity {
        case .cycling:
            return ATHLTHLocalization.choose(
                english: "Cycling workouts",
                norwegian: "Sykkeløkter"
            )
        case .swimming:
            return ATHLTHLocalization.choose(
                english: "Swimming workouts",
                norwegian: "Svømmeøkter"
            )
        case .hiking:
            return ATHLTHLocalization.choose(
                english: "Hiking workouts",
                norwegian: "Turøkter"
            )
        case .hiit:
            return "HIIT"
        case .rowing:
            return ATHLTHLocalization.choose(
                english: "Rowing workouts",
                norwegian: "Roøkter"
            )
        case .elliptical:
            return ATHLTHLocalization.choose(
                english: "Elliptical workouts",
                norwegian: "Ellipseøkter"
            )
        case .stairClimbing:
            return ATHLTHLocalization.choose(
                english: "Stair climbing workouts",
                norwegian: "Trappeøkter"
            )
        case .yoga:
            return ATHLTHLocalization.choose(
                english: "Yoga workouts",
                norwegian: "Yogaøkter"
            )
        case .coreTraining:
            return ATHLTHLocalization.choose(
                english: "Core workouts",
                norwegian: "Kjerneøkter"
            )
        case .other:
            return ATHLTHLocalization.choose(
                english: "Other workouts",
                norwegian: "Andre økter"
            )
        case .running, .walking, .strength:
            // These workouts are already represented by the four
            // standard values and cannot enter the other group.
            return ATHLTHLocalization.choose(
                english: "Other workouts",
                norwegian: "Andre økter"
            )
        }
    }

    private var visibleWeekDurationText:
        String {
        guard visibleWeekDurationMinutes >
                0
        else {
            return "—"
        }

        let total =
            Int(
                visibleWeekDurationMinutes
                    .rounded()
            )
        let hours =
            total / 60
        let minutes =
            total % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        return
            minutes == 0
                ? "\(hours)t"
                : "\(hours)t \(minutes)m"
    }

    private var plannedCount:
        Int {
        visibleWeekDates.reduce(0) {
            $0 +
                plannedSessions(
                    for: $1
                )
                .count
        }
    }

    // Weekly progress is activity based: every completed workout counts,
    // while unfinished planned sessions remain in the denominator.
    private var completedCount:
        Int {
        // Health-recorded workouts count once. Confirmed planned sessions
        // without a corresponding Health workout also count (e.g. a
        // manually completed plan workout or a Watch strength result
        // awaiting Health synchronisation).
        var completed = visibleWorkouts.count

        for date in visibleWeekDates {
            let planned = plannedSessions(for: date)
            let confirmedIDs = completedPlanSessionIDs(
                date: date, planned: planned
            )
            let recorded = workoutsForDay(date)

            for item in planned where confirmedIDs.contains(item.id) {
                if let plan,
                   let linkedID = session.linkedHealthWorkoutID(
                    planID: plan.id,
                    sessionID: item.id
                   ),
                   recorded.contains(where: { $0.id == linkedID }) {
                    continue
                }

                let recordedStrength = strength.workoutHistory.contains {
                    $0.isFinished && $0.plannedSessionID == item.id
                }
                if recordedStrength &&
                    recorded.contains(where: { $0.activity == .strength }) {
                    continue
                }

                // Never guess that an unrelated same-day Health workout
                // fulfills this manually confirmed planned session.
                completed += 1
            }
        }

        return completed
    }

    private var unfinishedPlannedCount:
        Int {
        visibleWeekDates.reduce(
            0
        ) { total, date in
            let planned =
                plannedSessions(
                    for: date
                )
            let completed =
                completedPlanSessionIDs(
                    date: date,
                    planned: planned
                )
            let scheduledCommunityEvents =
                communityEventsForDay(
                    date
                )
            let completedCommunity =
                completedCommunityEventIDs(
                    date: date,
                    events:
                        scheduledCommunityEvents
                )

            return total +
                max(
                    planned.count -
                        completed.count,
                    0
                ) +
                max(
                    scheduledCommunityEvents
                        .count -
                    completedCommunity
                        .count,
                    0
                )
        }
    }

    private var weeklyTotalCount:
        Int {
        completedCount +
            unfinishedPlannedCount
    }

    private var progress:
        Double {
        guard weeklyTotalCount > 0
        else {
            return 0
        }

        return min(
            Double(completedCount) /
                Double(weeklyTotalCount),
            1
        )
    }

    private var progressText:
        String {
        "\(completedCount) av \(weeklyTotalCount)"
    }

    private func workoutsForDay(
        _ date: Date
    ) -> [WorkoutSummary] {
        workouts
            .filter {
                calendar.isDate(
                    $0.startDate,
                    inSameDayAs:
                        date
                )
            }
            .sorted {
                $0.startDate <
                    $1.startDate
            }
    }

    private func communityEventsForDay(
        _ date: Date
    ) -> [HomeScheduledCommunityEvent] {
        events
            .filter {
                calendar.isDate(
                    $0.startsAt,
                    inSameDayAs:
                        date
                )
            }
            .sorted {
                $0.startsAt <
                    $1.startsAt
            }
    }

    private func completedCommunityEventIDs(
        date: Date,
        events:
            [HomeScheduledCommunityEvent]
    ) -> Set<String> {
        guard !events.isEmpty
        else {
            return []
        }

        var completed =
            Set<String>()
        var unused =
            workoutsForDay(date)

        for event in events {
            guard let index =
                    unused.firstIndex(
                        where: {
                            healthWorkout(
                                $0,
                                matchesCommunityActivity:
                                    event.activityType
                            )
                        }
                    )
            else {
                continue
            }

            completed.insert(
                event.id
            )
            unused.remove(
                at: index
            )
        }

        return completed
    }

    private func healthWorkout(
        _ workout: WorkoutSummary,
        matchesCommunityActivity
            activityType: String
    ) -> Bool {
        switch activityType {
        case "running":
            return workout.activity ==
                .running
        case "walking":
            return workout.activity ==
                .walking ||
                workout.activity ==
                    .hiking
        case "hike":
            return workout.activity ==
                .hiking ||
                workout.activity ==
                    .walking
        case "strength":
            return workout.activity ==
                .strength
        case "cycling":
            return workout.activity ==
                .cycling
        case "group_workout":
            return workout.activity ==
                .hiit ||
                workout.activity ==
                    .other
        default:
            return workout.activity ==
                .other ||
                workout.activity ==
                    .hiit ||
                workout.activity ==
                    .rowing ||
                workout.activity ==
                    .stairClimbing
        }
    }

    private func completedPlanSessionIDs(
        date: Date,
        planned: [PlannedSession]
    ) -> Set<UUID> {
        guard let plan else { return [] }

        return Set(
            planned.filter {
                session.isPlanSessionCompleted(
                    planID: plan.id,
                    sessionID: $0.id,
                    healthWorkouts: workouts,
                    strengthHistory: strength.workoutHistory
                )
            }
            .map(\.id)
        )
    }

    private func plannedSessions(
        for date: Date
    ) -> [PlannedSession] {
        // A day contains both scheduled plan workouts and independently
        // planned sessions, including workouts awaiting a friend's reply.
        let standalone = session.standalonePlannedSessions(on: date)
        guard let plan,
              !plan.weeks.isEmpty
        else {
            return standalone
        }

        let weekIndex: Int
        let dayIndex: Int

        if let startDate = plan.startDate {
            guard let position = HomeWeeklyProgressCalendar.planPosition(
                for: date,
                startDate: startDate,
                calendar: calendar
            ) else {
                return standalone
            }
            weekIndex = position.weekIndex
            dayIndex = position.dayIndex
        } else {
            // Legacy undated plans are anchored to the current week.
            let weekStart = calendar.dateInterval(
                of: .weekOfYear,
                for: date
            )?.start ?? calendar.startOfDay(for: date)
            let elapsed = calendar.dateComponents(
                [.day],
                from: currentWeekInterval.start,
                to: weekStart
            ).day ?? 0
            guard elapsed >= 0 else { return standalone }
            weekIndex = elapsed / 7
            let weekday = calendar.component(.weekday, from: date)
            dayIndex = ((weekday + 5) % 7) + 1
        }

        guard plan.weeks.indices.contains(weekIndex) else {
            return standalone
        }

        let scheduled = plan.weeks[
            weekIndex
        ]
        .days
        .first(
            where: {
                $0.dayIndex == dayIndex
            }
        )?
        .sessions ?? []

        // Never show duplicates if a workout also exists in a plan.
        let standaloneIDs = Set(standalone.map(\.id))
        return (scheduled.filter { !standaloneIDs.contains($0.id) } +
                standalone)
            .sorted {
                ($0.scheduledStart ?? .distantFuture) <
                    ($1.scheduledStart ?? .distantFuture)
            }
    }

    private func dayName(
        _ date: Date
    ) -> String {
        switch
            calendar.component(
                .weekday,
                from: date
            ) {
        case 2:
            return "Man"
        case 3:
            return "Tir"
        case 4:
            return "Ons"
        case 5:
            return "Tor"
        case 6:
            return "Fre"
        case 7:
            return "Lør"
        default:
            return "Søn"
        }
    }
}

private struct HomeWeeklyProgressDaySheet: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @EnvironmentObject private var runningLibrary: RunningWorkoutLibraryStore
    @EnvironmentObject private var messaging: MessagingStore

    let selection: HomeWeeklyProgressDaySelection
    let plan: TrainingPlan?
    let onOpenWorkout: () -> Void

    @StateObject private var workoutCatalog = WorkoutTemplateCatalogStore()
    @State private var showingStandaloneSessionEditor = false
    @State private var showingWorkoutPicker = false
    @State private var pendingPickedWorkout: PlannedSession?
    @State private var selectedSuggestion: PlannedSession?
    @State private var suggestionStartTime = Date()
    @State private var selectedInvitationLobby: PlannedSession?
    @State private var selectedMode = 0

    private let dayInk = Color(red: 0.17, green: 0.21, blue: 0.29)
    private let dayCanvas = Color(red: 0.968, green: 0.971, blue: 0.985)

    private var currentPlanned: [PlannedSession] {
        // Selection is a snapshot. Observe the saved standalone sessions so
        // the newly scheduled workout appears immediately in "Dagens økt".
        let standalone = session.standalonePlannedSessions(on: selection.date)
        let standaloneIDs = Set(standalone.map(\.id))
        return (selection.planned.filter {
            !standaloneIDs.contains($0.id)
        } + standalone)
        .sorted {
            ($0.scheduledStart ?? .distantFuture) <
                ($1.scheduledStart ?? .distantFuture)
        }
    }

    private var canPlanWorkout: Bool {
        HomeWeeklyProgressCalendar.canScheduleStandalone(on: selection.date)
    }

    private var hasAnyWorkoutsToday: Bool {
        !currentPlanned.isEmpty ||
        !selection.communityEvents.isEmpty ||
        !selection.actual.isEmpty
    }

    private var workoutSuggestions: [PlannedSession] {
        // Reuse real recipes; prioritize diverse training types instead of
        // showing three HYROX tiles simply because they sort first.
        let saved = session.savedWorkoutTemplates
        let savedTemplateIDs = Set(saved.compactMap(\.workoutTemplateID))
        let catalog = workoutCatalog.entries.filter {
            !savedTemplateIDs.contains($0.id)
        }
        let runs = runningLibrary.allTemplates
        let highlights: [PlannedSession] = [
            catalog.first(where: {
                $0.category == "strength" &&
                ($0.difficulty == "Beginner" || $0.difficulty == "Nybegynner")
            })?.plannedSession(),
            runs.first(where: { $0.isBuiltIn })?.plannedSession(),
            catalog.first(where: { $0.category == "hybrid" })?.plannedSession()
        ].compactMap { $0 }
        let all = highlights + saved + catalog.map { $0.plannedSession() } +
            runs.map { $0.plannedSession() }
        var distinct: [PlannedSession] = []
        var names: Set<String> = []
        for workout in all {
            let key = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !key.isEmpty && names.insert(key).inserted {
                distinct.append(workout)
            }
            if distinct.count == 4 { break }
        }
        return distinct
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text(selection.date.formatted(
                        .dateTime.weekday(.wide).day().month(.wide)
                    ))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(dayInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                    dayModeSelector

                    if selectedMode == 0 {
                        if hasAnyWorkoutsToday {
                            todaysWorkoutList
                        } else {
                            emptyTodayCard
                        }
                    } else {
                        planningCard
                    }

                    workoutSuggestionSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(dayCanvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingStandaloneSessionEditor) {
                SessionEditorView(standaloneDate: selection.date)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showingWorkoutPicker, onDismiss: {
                if let pending = pendingPickedWorkout {
                    pendingPickedWorkout = nil
                    presentSuggestion(pending)
                }
            }) {
                PlanWorkoutPickerView { workout in
                    pendingPickedWorkout = workout
                }
            }
            .sheet(item: $selectedSuggestion) { workout in
                suggestionDetail(workout)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $selectedInvitationLobby) { workout in
                PlannedWorkoutInvitationLobby(workout: workout)
                    .presentationDetents([.medium, .large])
            }
            .task {
                async let refreshWorkouts: Void = workoutCatalog.refresh()
                async let refreshMessages: Void = messaging.refresh(force: true)
                _ = await (refreshWorkouts, refreshMessages)
                session.syncApprovedSharedWorkouts(from: messaging.recentMessages)
            }
        }
    }

    private var dayModeSelector: some View {
        HStack(spacing: 3) {
            dayModeButton(
                ATHLTHLocalization.choose(english: "Today's workout", norwegian: "Dagens økt"),
                icon: "calendar",
                mode: 0
            )
            dayModeButton(
                ATHLTHLocalization.choose(english: "Plan new", norwegian: "Planlegg ny"),
                icon: "plus",
                mode: 1
            )
        }
        .padding(4)
        .background(dayInk.opacity(0.045), in: Capsule())
        .overlay {
            Capsule().strokeBorder(dayInk.opacity(0.11), lineWidth: 0.8)
        }
        .padding(.horizontal, 4)
    }

    private func dayModeButton(_ label: String, icon: String, mode: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedMode = mode
            }
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selectedMode == mode ? .white : dayInk)
                .frame(maxWidth: .infinity)
                .frame(height: 39)
                .background {
                    if selectedMode == mode {
                        Capsule().fill(dayInk)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
    }

    /// Compact empty state leaves the entire workout suggestion row visible.
    private var emptyTodayCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(dayInk)
                    .frame(width: 48, height: 48)
                    .background(dayInk.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 5) {
                    Text(ATHLTHLocalization.choose(
                        english: "No workout planned",
                        norwegian: "Ingen planlagt økt"
                    ))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(dayInk)

                    Text(ATHLTHLocalization.choose(
                        english: "Choose a ready-made session below, or create your own.",
                        norwegian: "Velg en ferdig økt nedenfor, eller lag din egen."
                    ))
                    .font(.system(size: 13))
                    .foregroundStyle(dayInk.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if canPlanWorkout {
                Button {
                    selectedMode = 1
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(ATHLTHLocalization.choose(
                            english: "Plan a workout", norwegian: "Planlegg en økt"
                        ))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(dayInk)
                    .padding(.horizontal, 13)
                    .frame(height: 39)
                    .background(dayInk.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(dayInk.opacity(0.07), lineWidth: 0.8)
        }
    }

    private var planningCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(ATHLTHLocalization.choose(
                english: "An extra workout, your way",
                norwegian: "En ekstra økt, på din måte"
            ), systemImage: "calendar.badge.plus")
                .font(.headline)
                .foregroundStyle(dayInk)

            Text(ATHLTHLocalization.choose(
                english: "Choose a workout from Workouts, or create a new one. Nothing changes in your training plan.",
                norwegian: "Velg en økt fra Workouts eller lag en ny. Treningsplanen din endres ikke."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if canPlanWorkout {
                Button {
                    showingStandaloneSessionEditor = true
                } label: {
                    Label(ATHLTHLocalization.choose(
                        english: "Create workout", norwegian: "Planlegg egen økt"
                    ), systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 47)
                    .background(dayInk, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private var workoutSuggestionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Suggestions from Workouts",
                    norwegian: "Forslag fra Workouts"
                ))
                .font(.headline)
                .foregroundStyle(dayInk)
                Spacer()
                Button {
                    showingWorkoutPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(ATHLTHLocalization.choose(english: "See all", norwegian: "Se alle"))
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(dayInk.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if workoutSuggestions.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Explore the Workouts library to find ready-made sessions.",
                    norwegian: "Utforsk Workouts-biblioteket for ferdige treningsøkter."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(workoutSuggestions.enumerated()), id: \.offset) { index, workout in
                        Button {
                            presentSuggestion(workout)
                        } label: {
                            suggestionTile(workout, index: index)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func suggestionTile(_ workout: PlannedSession, index: Int) -> some View {
        let accents: [Color] = [
            Color(red: 0.88, green: 0.49, blue: 0.34),
            Color(red: 0.29, green: 0.58, blue: 0.88),
            Color(red: 0.31, green: 0.68, blue: 0.50),
            Color(red: 0.57, green: 0.46, blue: 0.82)
        ]
        let accent = accents[index % accents.count]

        return VStack(alignment: .leading, spacing: 7) {
            Image(systemName: workout.kind.systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(dayInk)
                .frame(height: 30, alignment: .leading)

            Text(workout.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dayInk)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                Text(workout.durationMinutes.map { "\($0) min" }
                     ?? ATHLTHLocalization.choose(english: "Workout", norwegian: "Økt"))
                    .font(.system(size: 10))
                    .foregroundStyle(dayInk.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(dayInk)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(10)
        .background(accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.08), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Review and schedule this Workouts session",
            norwegian: "Se detaljer og planlegg denne økten"
        ))
    }

    private var todaysWorkoutList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ATHLTHLocalization.choose(english: "Today", norwegian: "I dag"))
                    .font(.headline)
                    .foregroundStyle(dayInk)
                Spacer()
                if canPlanWorkout {
                    Button {
                        selectedMode = 1
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Add workout", norwegian: "Legg til økt"
                        ), systemImage: "plus")
                        .font(.caption.weight(.semibold))
                    }
                    .tint(dayInk)
                }
            }

            if !currentPlanned.isEmpty {
                sectionTitle(ATHLTHLocalization.choose(
                    english: "Planned", norwegian: "Planlagt"
                ))
                ForEach(currentPlanned) { workout in
                    if workout.trainTogetherMode != nil {
                        Button {
                            selectedInvitationLobby = workout
                        } label: {
                            plannedRowContent(workout)
                        }
                        .buttonStyle(.plain)
                    } else {
                        plannedRow(workout)
                    }
                }
            }

            if !selection.communityEvents.isEmpty {
                sectionTitle(ATHLTHLocalization.choose(
                    english: "Events", norwegian: "Arrangementer"
                ))
                ForEach(selection.communityEvents) { event in
                    communityEventRow(event)
                }
            }

            if !selection.actual.isEmpty {
                sectionTitle(ATHLTHLocalization.choose(
                    english: "Completed workouts", norwegian: "Utførte økter"
                ))
                ForEach(selection.actual) { workout in
                    NavigationLink {
                        completedWorkoutDestination(workout)
                            .onAppear(perform: onOpenWorkout)
                    } label: {
                        actualRow(workout)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.86),
                    in: RoundedRectangle(cornerRadius: 23))
    }

    private func presentSuggestion(_ workout: PlannedSession) {
        let preferredStart = Calendar.current.date(
            bySettingHour: 18, minute: 0, second: 0,
            of: selection.date
        ) ?? selection.date
        let now = Date()
        suggestionStartTime = Calendar.current.isDateInToday(selection.date)
            && preferredStart <= now
            ? now.addingTimeInterval(15 * 60)
            : preferredStart
        selectedSuggestion = workout
    }

    private func suggestionDetail(_ workout: PlannedSession) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    ATHLTHWorkoutRecipePreview(
                        title: workout.title,
                        summary: workout.notes ?? "",
                        category: workout.workoutCategory ??
                            (workout.kind == .strength ? "strength" :
                             workout.kind == .running ? "running" :
                             workout.kind == .walking ? "walking" : "hybrid"),
                        symbol: workout.kind.systemImage,
                        difficulty: nil,
                        durationMinutes: workout.durationMinutes,
                        blocks: ATHLTHUnifiedWorkout.editorBlocks(from: workout)
                    )

                    if canPlanWorkout {
                        DatePicker(
                            ATHLTHLocalization.choose(english: "Time", norwegian: "Tidspunkt"),
                            selection: $suggestionStartTime,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.compact)
                        .padding(.vertical, 10)

                        if !HomeWorkoutSuggestionPlanner.canSchedule(
                            on: selection.date, at: suggestionStartTime
                        ) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Choose a future time on this date.",
                                    norwegian: "Velg et fremtidig tidspunkt på denne datoen."
                                ),
                                systemImage: "clock.badge.exclamationmark"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Button {
                            guard HomeWorkoutSuggestionPlanner.canSchedule(
                                on: selection.date, at: suggestionStartTime
                            ) else { return }
                            let copy = HomeWorkoutSuggestionPlanner.independentSession(
                                from: workout, start: suggestionStartTime
                            )
                            session.addStandalonePlannedSession(copy)
                            selectedSuggestion = nil
                            selectedMode = 0
                        } label: {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Plan this workout", norwegian: "Planlegg denne økten"
                                ), systemImage: "calendar.badge.plus"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 49)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(dayInk)
                        .disabled(!HomeWorkoutSuggestionPlanner.canSchedule(
                            on: selection.date, at: suggestionStartTime
                        ))
                    }
                }
                .padding(20)
            }
            .background(dayCanvas.ignoresSafeArea())
            .navigationTitle(
                ATHLTHLocalization.choose(english: "Workout", norwegian: "Treningsøkt")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Close", norwegian: "Lukk"
                    )) {
                        selectedSuggestion = nil
                    }
                }
            }
        }
    }

    private func sectionTitle(
        _ title: String
    ) -> some View {
        Text(title.uppercased())
            .font(
                .system(
                    size: 9,
                    weight: .bold
                )
            )
            .tracking(1.0)
            .foregroundStyle(
                ATHLTHTheme.mutedText
            )
            .padding(.top, 4)
    }

    @ViewBuilder
    private func plannedRow(
        _ workout: PlannedSession
    ) -> some View {
        if let planID = HomeWeeklyProgressCalendar.containingPlanID(
            for: workout,
            in: plan
        ) {
            NavigationLink {
                PlannedWorkoutDetailView(
                    planID: planID,
                    workout: workout,
                    isHealthCompleted: false
                )
                .onAppear(perform: onOpenWorkout)
            } label: {
                plannedRowContent(workout)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english: "Open details for this planned workout",
                    norwegian: "Åpne detaljer for denne planlagte økten"
                )
            )
        } else {
            NavigationLink {
                HomeWeeklyStandaloneWorkoutDetailView(workout: workout)
                    .onAppear(perform: onOpenWorkout)
            } label: {
                plannedRowContent(workout)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                ATHLTHLocalization.choose(
                    english: "Open details for this calendar workout",
                    norwegian: "Åpne detaljer for denne kalenderøkten"
                )
            )
        }
    }

    private func plannedRowContent(
        _ workout: PlannedSession
    ) -> some View {
        let completed =
            selection
                .completedPlannedIDs
                .contains(
                    workout.id
                )

        return HStack(spacing: 11) {
            Image(
                systemName:
                    completed
                        ? "checkmark"
                        : workout
                            .kind
                            .systemImage
            )
            .font(
                .system(
                    size: 13,
                    weight: .bold
                )
            )
            .foregroundStyle(
                completed
                    ? .white
                    : ATHLTHTheme
                        .accentDeep
            )
            .frame(
                width: 36,
                height: 36
            )
            .background(
                completed
                    ? ATHLTHTheme
                        .vitality
                    : ATHLTHTheme
                        .accentSoft,
                in: Circle()
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(workout.title)
                    .font(
                        .subheadline
                            .weight(.semibold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme.primaryText
                    )
                    .lineLimit(1)

                Text(
                    plannedDetail(
                        workout
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
                .lineLimit(1)

                if workout.trainTogetherMode != nil && !completed {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Friend invited · tap for lobby and status",
                            norwegian: "Venn invitert · åpne lobby og status"
                        ),
                        systemImage: "person.crop.circle.badge.clock"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .lineLimit(1)
                }
            }

            Spacer()

            Text(
                completed
                    ? ATHLTHLocalization.choose(
                        english:
                            "Completed",
                        norwegian:
                            "Fullført"
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "Planned",
                        norwegian:
                            "Planlagt"
                    )
            )
            .font(
                .caption2.weight(
                    .semibold
                )
            )
            .foregroundStyle(
                completed
                    ? ATHLTHTheme
                        .vitality
                    : ATHLTHTheme
                        .mutedText
            )
        }
        .padding(11)
        .background(
            Color.white.opacity(0.92),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    private func communityEventRow(
        _ event:
            HomeScheduledCommunityEvent
    ) -> some View {
        let completed =
            selection
                .completedCommunityEventIDs
                .contains(
                    event.id
                )

        return HStack(spacing: 11) {
            Image(
                systemName:
                    completed
                        ? "checkmark"
                        : event.systemImage
            )
            .font(
                .system(
                    size: 13,
                    weight: .bold
                )
            )
            .foregroundStyle(
                completed
                    ? .white
                    : ATHLTHTheme
                        .accentDeep
            )
            .frame(
                width: 36,
                height: 36
            )
            .background(
                completed
                    ? ATHLTHTheme
                        .vitality
                    : ATHLTHTheme
                        .accentSoft,
                in: Circle()
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(event.title)
                    .font(
                        .subheadline
                            .weight(
                                .semibold
                            )
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )
                    .lineLimit(2)

                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(
                        ATHLTHTheme
                            .mutedText
                    )
                    .lineLimit(1)
            }

            Spacer()

            Text(
                completed
                    ? ATHLTHLocalization.choose(
                        english:
                            "Completed",
                        norwegian:
                            "Fullført"
                    )
                    : ATHLTHLocalization.choose(
                        english:
                            "Event",
                        norwegian:
                            "Event"
                    )
            )
            .font(
                .caption2.weight(
                    .semibold
                )
            )
            .foregroundStyle(
                completed
                    ? ATHLTHTheme
                        .vitality
                    : ATHLTHTheme
                        .mutedText
            )
        }
        .padding(11)
        .background(
            Color.white.opacity(0.92),
            in: RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }

    @ViewBuilder
    private func completedWorkoutDestination(
        _ summary: WorkoutSummary
    ) -> some View {
        // Both the workout created in ATHLTH and its HealthKit record may
        // carry the same HealthKit UUID. Prefer the ATHLTH strength log
        // so sets, exercises, weights and personal records are available.
        let strengthLog = strength.workoutHistory.first {
            $0.id == summary.id ||
            $0.healthMetrics.healthKitWorkoutUUID == summary.id
        }
        let workout = strengthLog.map {
            SocialPublishableWorkout(strengthWorkout: $0)
        } ?? SocialPublishableWorkout(summary: summary)

        switch workout.activity {
        case .strength:
            if let strengthLog {
                HomeActivityStrengthDetailView(
                    workout: workout,
                    strengthWorkout: strengthLog
                )
            } else {
                // HealthKit-only strength sessions have no ATHLTH sets or
                // exercise log. Show their actual HealthKit metrics instead
                // of displaying empty set counts in the strength editor.
                WorkoutHistoryDetailView(workout: workout)
            }
        case .running, .walking, .hiking:
            HomeActivityRunDetailView(
                workout: workout,
                initialDetail: nil,
                initialAIInsight: nil
            )
        default:
            WorkoutHistoryDetailView(workout: workout)
        }
    }

    // Planned sessions keep their original compact time, duration,
    // distance and exercise summary. This helper was inadvertently removed
    // while the completed-workout cards were upgraded.
    private func plannedDetail(
        _ workout: PlannedSession
    ) -> String {
        var parts: [String] = []

        if let start = workout.scheduledStart {
            parts.append(
                start.formatted(date: .omitted, time: .shortened)
            )
        }

        if let minutes = workout.durationMinutes {
            parts.append("\(minutes) min")
        }

        if let distance = workout.targetDistanceKilometers {
            parts.append(
                String(format: "%.1f km", distance)
            )
        }

        if !workout.exercises.isEmpty {
            parts.append(
                ATHLTHLocalization.format(
                    english: "%d exercises",
                    norwegian: "%d øvelser",
                    workout.exercises.count
                )
            )
        }

        return parts.isEmpty
            ? workout.kind.title
            : parts.joined(separator: " · ")
    }

    private func actualRow(
        _ workout: WorkoutSummary
    ) -> some View {
        let metrics = HomeCompletedWorkoutPresentation.metrics(for: workout)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: workout.activity.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.accentDeep)
                    .frame(width: 42, height: 42)
                    .background(
                        ATHLTHTheme.accentSoft.opacity(0.78),
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        workout.activity == .running && workout.isIndoor == true
                            ? ATHLTHLocalization.choose(
                                english: "Treadmill",
                                norwegian: "Tredemølle"
                            )
                            : HomeCompletedWorkoutPresentation.title(
                                for: workout.activity
                            )
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                    .lineLimit(1)

                    Text(HomeCompletedWorkoutPresentation.timeAndLocation(
                        for: workout
                    ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
                }

                Spacer(minLength: 5)

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ATHLTHTheme.vitality)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .accessibilityLabel(
                    ATHLTHLocalization.choose(
                        english: "Completed. Open details",
                        norwegian: "Fullført. Åpne detaljer"
                    )
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 7),
                    GridItem(.flexible(), spacing: 7)
                ],
                alignment: .leading,
                spacing: 7
            ) {
                ForEach(metrics) { metric in
                    HStack(spacing: 6) {
                        Image(systemName: metric.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                            .frame(width: 14)

                        Text(metric.text)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 29)
                    .background(
                        ATHLTHTheme.accentSoft.opacity(0.25),
                        in: RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )
                }
            }
        }
        .padding(12)
        .background(
            Color.white.opacity(0.94),
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
            .stroke(Color.primary.opacity(0.045), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
    }

}

// The HealthKit summary intentionally contains no set count or average
// heart rate. Show only values that were actually recorded; do not invent
// strength stats or pulse measurements for compact Home cards.
struct HomeCompletedWorkoutMetric: Identifiable {
    let id: String
    let icon: String
    let text: String
}

enum HomeCompletedWorkoutPresentation {
    static func title(
        for activity: WorkoutActivity,
        norwegian: Bool = ATHLTHLocalization.isNorwegian
    ) -> String {
        guard norwegian else { return activity.rawValue }
        switch activity {
        case .running: return "Løping"
        case .walking: return "Gåtur"
        case .cycling: return "Sykling"
        case .swimming: return "Svømming"
        case .hiking: return "Fottur"
        case .strength: return "Styrke"
        case .hiit: return "Intervalltrening"
        case .rowing: return "Roing"
        case .elliptical: return "Ellipsemaskin"
        case .stairClimbing: return "Trappetrening"
        case .yoga: return "Yoga"
        case .coreTraining: return "Kjernetrening"
        case .other: return "Trening"
        }
    }

    static func timeAndLocation(
        for workout: WorkoutSummary,
        norwegian: Bool = ATHLTHLocalization.isNorwegian
    ) -> String {
        let start = workout.startDate.formatted(
            date: .omitted, time: .shortened
        )
        let end = workout.endDate.formatted(
            date: .omitted, time: .shortened
        )
        let range = workout.endDate > workout.startDate
            ? "\(start)–\(end)" : start

        let location: String?
        switch workout.isIndoor {
        case .some(true):
            location = norwegian ? "Inne" : "Indoor"
        case .some(false):
            location = norwegian ? "Ute" : "Outdoor"
        case .none:
            location = nil
        }
        return [range, location].compactMap { $0 }.joined(separator: " · ")
    }

    static func metrics(
        for workout: WorkoutSummary,
        norwegian: Bool = ATHLTHLocalization.isNorwegian
    ) -> [HomeCompletedWorkoutMetric] {
        var items: [HomeCompletedWorkoutMetric] = []
        let seconds = workout.duration
        if seconds.isFinite && seconds >= 0 {
            let minutes = max(Int((seconds / 60).rounded()), 0)
            let duration: String
            if minutes >= 60 {
                let hours = minutes / 60
                let remaining = minutes % 60
                duration = norwegian
                    ? "\(hours) t \(remaining) min"
                    : "\(hours) h \(remaining) min"
            } else {
                duration = "\(minutes) min"
            }
            items.append(.init(
                id: "duration",
                icon: "clock",
                text: duration
            ))
        }

        if let meters = workout.distanceMeters,
           meters.isFinite, meters > 0 {
            let kilometers = meters / 1_000
            let formatted = kilometers.formatted(
                .number
                    .precision(.fractionLength(1))
                    .locale(Locale(identifier: norwegian ? "nb_NO" : "en_US"))
            )
            items.append(.init(
                id: "distance",
                icon: "point.topleft.down.curvedto.point.bottomright.up",
                text: "\(formatted) km"
            ))

            if seconds.isFinite, seconds > 0, kilometers >= 0.25 {
                switch workout.activity {
                case .running, .walking, .hiking:
                    let paceSeconds = seconds / kilometers
                    if paceSeconds.isFinite &&
                       paceSeconds >= 120 &&
                       paceSeconds <= 2_700 {
                        let rounded = Int(paceSeconds.rounded())
                        let time = String(
                            format: "%d:%02d",
                            rounded / 60, rounded % 60
                        )
                        items.append(.init(
                            id: "pace",
                            icon: "speedometer",
                            text: "\(time) min/km"
                        ))
                    }
                case .cycling:
                    let kilometersPerHour = kilometers / (seconds / 3_600)
                    if kilometersPerHour.isFinite,
                       kilometersPerHour > 0,
                       kilometersPerHour <= 120 {
                        let speed = kilometersPerHour.formatted(
                            .number
                                .precision(.fractionLength(1))
                                .locale(Locale(identifier: norwegian ? "nb_NO" : "en_US"))
                        )
                        items.append(.init(
                            id: "speed",
                            icon: "speedometer",
                            text: "\(speed) km/t"
                        ))
                    }
                default:
                    break
                }
            }
        }

        if let energy = workout.activeEnergyKilocalories,
           energy.isFinite, energy > 0 {
            items.append(.init(
                id: "energy",
                icon: "flame",
                text: "\(Int(energy.rounded())) kcal"
            ))
        }

        return items
    }
}

struct HomeWeeklySummaryCard:
    View {
    let runningDistanceKilometers:
        Double
    let durationMinutes: Double
    let strengthSessions: Int
    let sessionCount: Int

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack(spacing: 7) {
                Image(
                    systemName:
                        "chart.bar.fill"
                )
                .font(
                    .system(
                        size: 14,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.blue)

                Text("Denne uken")
                    .font(
                        .headline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Spacer()
            }

            HStack(spacing: 7) {
                weeklyMetric(
                    icon: "figure.run",
                    value:
                        runningDistanceKilometers >
                            0
                            ? String(
                                format:
                                    "%.1f km",
                                locale:
                                    Locale
                                        .current,
                                runningDistanceKilometers
                            )
                            : "—"
                )

                weeklyMetric(
                    icon:
                        "stopwatch.fill",
                    value:
                        formattedDuration
                )

                weeklyMetric(
                    icon:
                        "dumbbell.fill",
                    value:
                        "\(strengthSessions)"
                )

                weeklyMetric(
                    icon:
                        "checkmark.circle.fill",
                    value:
                        "\(sessionCount)"
                )
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(
                        0.045
                    ),
                    Color.white.opacity(
                        0.92
                    )
                ],
                startPoint:
                    .topLeading,
                endPoint:
                    .bottomTrailing
            ),
            in: RoundedRectangle(
                cornerRadius: 19,
                style: .continuous
            )
        )
    }

    private func weeklyMetric(
        icon: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 12,
                    weight: .semibold
                )
            )
            .foregroundStyle(
                ATHLTHTheme
                    .accentDeep
            )

            Text(value)
                .font(
                    .system(
                        size: 14,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    ATHLTHTheme
                        .primaryText
                )
                .lineLimit(1)
                .minimumScaleFactor(
                    0.62
                )
        }
        .padding(
            .horizontal,
            9
        )
        .padding(
            .vertical,
            9
        )
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.white.opacity(
                0.86
            ),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var formattedDuration:
        String {
        guard durationMinutes > 0
        else {
            return "—"
        }

        let total =
            Int(
                durationMinutes
                    .rounded()
            )
        let hours = total / 60
        let minutes =
            total % 60

        if hours == 0 {
            return "\(minutes) min"
        }

        return
            "\(hours)t \(minutes)m"
    }
}


private struct PlannedWorkoutInvitationLobby: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var messaging: MessagingStore
    @EnvironmentObject private var social: SocialStore
    @Environment(\.dismiss) private var dismiss

    let workout: PlannedSession
    @State private var isRefreshing = false

    private var sourceID: UUID {
        workout.sharedSourceSessionID ?? workout.id
    }

    private var isGuest: Bool {
        workout.sharedSourceOwnerID != nil
    }

    private var otherUserID: UUID? {
        workout.sharedSourceOwnerID ?? workout.invitedPartnerID
    }

    private var invitationMessages: [DirectMessageRecord] {
        guard let otherUserID,
              let conversation = messaging.conversation(with: otherUserID)
        else { return messaging.recentMessages }
        return messaging.messages(in: conversation.id).isEmpty
            ? messaging.recentMessages.filter {
                $0.conversationID == conversation.id
            }
            : messaging.messages(in: conversation.id)
    }

    private var wasSent: Bool {
        invitationMessages.contains {
            $0.attachmentKind == .workout &&
            $0.shareVersion == 2 &&
            $0.sourceObjectID == sourceID &&
            $0.deletedAt == nil
        }
    }

    private var response: PlannedWorkoutInviteDecision? {
        guard let replyingUserID = isGuest
            ? Optional(session.profile.userID) : workout.invitedPartnerID
        else { return nil }

        return invitationMessages
            .filter {
                $0.attachmentKind == .workout &&
                $0.shareVersion == 3 &&
                $0.sourceObjectID == sourceID &&
                $0.senderID == replyingUserID &&
                $0.deletedAt == nil
            }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap {
                $0.decodeSnapshot(PlannedWorkoutInviteResponse.self)
            }
            .first { $0.sourceWorkoutID == sourceID }?
            .decision
    }

    private var status: (title: String, detail: String, icon: String, tint: Color) {
        if isGuest || response == .accepted {
            return (
                "Godtatt", "Økten er lagt i deltakerens kalender.",
                "checkmark.circle.fill", ATHLTHTheme.vitality
            )
        }
        if response == .declined {
            return (
                "Avslått", "Du kan fortsatt gjennomføre økten alene.",
                "xmark.circle.fill", ATHLTHTheme.mutedText
            )
        }
        if wasSent {
            return (
                "Venter på svar", "Økten blir stående i kalenderen uansett svar.",
                "clock.fill", ATHLTHTheme.accentDeep
            )
        }
        return (
            "Invitasjon ikke bekreftet sendt",
            "Din egen økt er lagret. Kontroller invitasjonen i innboksen.",
            "exclamationmark.circle.fill", ATHLTHTheme.accentDeep
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "TRAINING LOBBY",
                                norwegian: "TRENINGSLOBBY"
                            ),
                            systemImage: "person.2.wave.2.fill"
                        )
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        Text(workout.title)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundStyle(ATHLTHTheme.primaryText)
                        HStack(spacing: 14) {
                            if let start = workout.scheduledStart {
                                Label(
                                    start.formatted(date: .abbreviated, time: .shortened),
                                    systemImage: "calendar"
                                )
                            }
                            if let duration = workout.durationMinutes {
                                Label("\(duration) min", systemImage: "clock")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Deltakere")
                            .font(.headline)

                        participantRow(
                            name: session.profile.displayName,
                            icon: "person.crop.circle.fill",
                            status: "Deg",
                            tint: ATHLTHTheme.vitality
                        )
                        if let otherUserID {
                            Divider()
                            HStack(spacing: 12) {
                                if let profile = social.profile(for: otherUserID) {
                                    SocialAvatar(profile: profile, size: 44)
                                } else {
                                    Image(systemName: "person.crop.circle")
                                        .font(.system(size: 32))
                                        .frame(width: 44, height: 44)
                                        .foregroundStyle(ATHLTHTheme.mutedText)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(
                                        social.profile(for: otherUserID)?.resolvedName ??
                                        (isGuest ? "Arrangør" : "Invitert deltaker")
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    HStack(spacing: 5) {
                                        Image(systemName: status.icon)
                                        Text(status.title)
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(status.tint)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(17)
                    .background(
                        Color.white.opacity(0.82),
                        in: RoundedRectangle(cornerRadius: 22)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.white.opacity(0.95))
                    }

                    Label(status.detail, systemImage: status.icon)
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.primaryText)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            status.tint.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 15)
                        )

                    if let point = workout.meetingPoint {
                        Label(point.name, systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    if isGuest {
                        Text("Økten er allerede i kalenderen din. Du kan foreslå endringer via invitasjonen i innboksen; arrangøren må godkjenne dem.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    } else {
                        Text("Du kan starte og gjennomføre økten selv om den inviterte ikke har svart eller har avslått.")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                    }

                    if workout.allowInviteeExercises == true {
                        Label(
                            "Invitert deltaker kan foreslå nye øvelser",
                            systemImage: "checkmark.shield.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    Button {
                        Task { await refresh() }
                    } label: {
                        HStack {
                            if isRefreshing { ProgressView().controlSize(.small) }
                            Label("Oppdater status", systemImage: "arrow.clockwise")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshing)
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHPremiumCanvas().ignoresSafeArea())
            .navigationTitle("Tren sammen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                }
            }
        }
        .task(id: workout.id) { await refresh() }
    }

    private func participantRow(
        name: String,
        icon: String,
        status: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 31))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tint)
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await messaging.refresh(force: true)
        if let otherUserID,
           let conversation = messaging.conversation(with: otherUserID) {
            await messaging.refreshConversation(conversation.id)
            session.syncApprovedSharedWorkouts(
                from: messaging.messages(in: conversation.id)
            )
        }
    }
}
