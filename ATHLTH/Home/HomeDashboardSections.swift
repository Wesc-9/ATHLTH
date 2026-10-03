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

private struct HomeMetricMiniBars:
    View {
    let values: [Double?]
    let tint: Color
    let zeroIsEmpty: Bool

    var body: some View {
        GeometryReader { proxy in
            let resolved =
                values.isEmpty
                    ? Array(
                        repeating: nil,
                        count: 7
                    )
                    : values
            let valid =
                resolved
                    .compactMap { $0 }
                    .filter {
                        $0.isFinite &&
                        $0 >= 0
                    }
            let rawMaximum =
                valid.max() ?? 0
            let maximum =
                zeroIsEmpty
                    ? roundedScaleMaximum(
                        rawMaximum
                    )
                    : max(
                        rawMaximum,
                        0.001
                    )

            HStack(
                alignment: .bottom,
                spacing: 3
            ) {
                ForEach(
                    Array(
                        resolved.enumerated()
                    ),
                    id: \.offset
                ) { _, value in
                    Capsule()
                        .fill(
                            value == nil
                                ? tint.opacity(
                                    0.10
                                )
                                : tint.opacity(
                                    0.66
                                )
                        )
                        .frame(
                            maxWidth:
                                .infinity
                        )
                        .frame(
                            height:
                                barHeight(
                                    value: value,
                                    maximum:
                                        maximum,
                                    availableHeight:
                                        proxy
                                            .size
                                            .height
                                )
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func roundedScaleMaximum(
        _ value: Double
    ) -> Double {
        guard value > 0 else {
            return 1
        }

        let magnitude =
            pow(
                10,
                floor(log10(value))
            )
        let normalized =
            value / magnitude
        let rounded:
            Double

        switch normalized {
        case ...1:
            rounded = 1
        case ...2:
            rounded = 2
        case ...4:
            rounded = 4
        case ...5:
            rounded = 5
        default:
            rounded = 10
        }

        return max(
            rounded * magnitude,
            value
        )
    }

    private func barHeight(
        value: Double?,
        maximum: Double,
        availableHeight: CGFloat
    ) -> CGFloat {
        guard let value,
              value.isFinite,
              value >= 0
        else {
            return 4
        }

        if zeroIsEmpty &&
            value <= 0 {
            return 0
        }

        return max(
            4,
            availableHeight *
                CGFloat(
                    min(
                        value / maximum,
                        1
                    )
                )
        )
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

                ATHLTHCard {
                    HStack(
                        alignment:
                            .firstTextBaseline
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

                        Spacer()

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

                ATHLTHCard {
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

private struct HomeWeeklyProgressDaySelection:
    Identifiable {
    var id: Date { date }

    let date: Date
    let planned: [PlannedSession]
    let actual: [WorkoutSummary]
    let completedPlannedIDs: Set<UUID>
}

struct HomeWeeklyProgressStrip:
    View {
    @EnvironmentObject private var session:
        AppSessionStore

    let plan: TrainingPlan?
    let workouts: [WorkoutSummary]

    @State private var weekOffset = 0
    @State private var selectedDay:
        HomeWeeklyProgressDaySelection?

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
            spacing: 8
        ) {
            HStack(spacing: 7) {
                Text("Ukens fremdrift")
                    .font(
                        .subheadline
                            .weight(.bold)
                    )
                    .foregroundStyle(
                        ATHLTHTheme
                            .primaryText
                    )

                Spacer()

                Text(progressText)
                    .font(
                        .caption
                            .weight(.semibold)
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
                y: 0.72,
                anchor: .center
            )

            HStack(spacing: 3) {
                if weekOffset > 0 {
                    weekNavigationButton(
                        systemImage:
                            "chevron.left"
                    ) {
                        withAnimation(
                            .snappy(
                                duration: 0.22
                            )
                        ) {
                            weekOffset =
                                max(
                                    weekOffset - 1,
                                    0
                                )
                        }
                    }
                }

                ForEach(
                    visibleWeekDates,
                    id: \.self
                ) { date in
                    dayButton(date)
                }

                weekNavigationButton(
                    systemImage:
                        "chevron.right",
                    enabled:
                        canAdvance
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
        }
        .padding(11)
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
                selection: selection
            )
            .presentationDetents(
                [.medium, .large]
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
        let completedIDs =
            completedPlanSessionIDs(
                date: date,
                planned: planned
            )

        Button {
            selectedDay =
                HomeWeeklyProgressDaySelection(
                    date: date,
                    planned: planned,
                    actual: actual,
                    completedPlannedIDs:
                        completedIDs
                )
        } label: {
            day(
                date,
                planned: planned,
                actual: actual,
                completedIDs:
                    completedIDs
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
        actual: [WorkoutSummary],
        completedIDs: Set<UUID>
    ) -> some View {
        let plannedSession =
            planned.first {
                !completedIDs
                    .contains($0.id)
            } ??
            planned.first
        let allPlannedCompleted =
            !planned.isEmpty &&
            completedIDs.count ==
                planned.count
        let hasUnplannedActual =
            planned.isEmpty &&
            !actual.isEmpty
        let isCompleted =
            allPlannedCompleted ||
            hasUnplannedActual
        let isToday =
            calendar.isDateInToday(
                date
            )

        return VStack(spacing: 4) {
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
                                        nil
                                            ? 1
                                            : 1.5,
                                    dash:
                                        plannedSession ==
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
                }
            }
            .frame(
                width: 30,
                height: 30
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
                    size: 9,
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
                width: 30,
                height: 30
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
                        "Next days",
                    norwegian:
                        "Neste dager"
                )
                : ATHLTHLocalization.choose(
                    english:
                        "Previous days",
                    norwegian:
                        "Forrige dager"
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
        let start =
            calendar.date(
                byAdding: .day,
                value:
                    weekOffset * 7,
                to:
                    currentWeekInterval
                        .start
            ) ??
            currentWeekInterval
                .start

        return DateInterval(
            start: start,
            duration:
                7 * 86_400
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
        visibleWorkouts.count
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

            return total +
                max(
                    planned.count -
                        completed.count,
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

    private var canAdvance:
        Bool {
        guard let plan,
              !plan.weeks.isEmpty
        else {
            return false
        }

        if let startDate =
                plan.startDate {
            let currentStart =
                calendar.startOfDay(
                    for:
                        currentWeekInterval
                            .start
                )
            let planStart =
                calendar.startOfDay(
                    for: startDate
                )
            let daysFromPlanStart =
                calendar
                    .dateComponents(
                        [.day],
                        from: planStart,
                        to: currentStart
                    )
                    .day ?? 0
            let currentPlanWeek =
                max(
                    daysFromPlanStart / 7,
                    0
                )
            let remaining =
                max(
                    plan.weeks.count -
                        currentPlanWeek -
                        1,
                    0
                )
            return weekOffset <
                remaining
        }

        return weekOffset <
            max(
                plan.weeks.count - 1,
                0
            )
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

    private func completedPlanSessionIDs(
        date: Date,
        planned: [PlannedSession]
    ) -> Set<UUID> {
        guard !planned.isEmpty
        else {
            return []
        }

        var completed =
            Set<UUID>()

        if let plan {
            for item in planned
            where session
                .isPlanSessionManuallyCompleted(
                    planID: plan.id,
                    sessionID: item.id
                ) {
                completed.insert(
                    item.id
                )
            }
        }

        var unused =
            workoutsForDay(date)

        for item in planned
        where !completed
            .contains(item.id) {
            guard let index =
                    unused.firstIndex(
                        where: {
                            healthWorkout(
                                $0,
                                matches: item
                            )
                        }
                    )
            else {
                continue
            }

            completed.insert(
                item.id
            )
            unused.remove(
                at: index
            )
        }

        return completed
    }

    private func healthWorkout(
        _ workout: WorkoutSummary,
        matches planned:
            PlannedSession
    ) -> Bool {
        switch planned.kind {
        case .running:
            return workout.activity ==
                .running
        case .walking:
            return workout.activity ==
                .walking ||
                workout.activity ==
                    .hiking
        case .strength:
            return workout.activity ==
                .strength
        case .mobility:
            return workout.activity ==
                .yoga ||
                workout.activity ==
                    .coreTraining
        case .recovery:
            return false
        case .custom:
            return workout.activity ==
                .hiit ||
                workout.activity ==
                    .rowing ||
                workout.activity ==
                    .cycling ||
                workout.activity ==
                    .stairClimbing ||
                workout.activity ==
                    .other
        }
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

        if let startDate =
                plan.startDate {
            let start =
                calendar
                    .startOfDay(
                        for: startDate
                    )
            let target =
                calendar
                    .startOfDay(
                        for: date
                    )
            let days =
                calendar
                    .dateComponents(
                        [.day],
                        from: start,
                        to: target
                    )
                    .day ?? 0

            guard days >= 0 else {
                return []
            }

            weekIndex =
                days / 7
        } else {
            let targetWeek =
                calendar.dateInterval(
                    of: .weekOfYear,
                    for: date
                )?
                .start ??
                calendar.startOfDay(
                    for: date
                )
            let days =
                calendar
                    .dateComponents(
                        [.day],
                        from:
                            currentWeekInterval
                                .start,
                        to: targetWeek
                    )
                    .day ?? 0
            weekIndex =
                max(
                    days / 7,
                    0
                )
        }

        guard
            plan.weeks.indices
                .contains(weekIndex)
        else {
            return []
        }

        let weekday =
            calendar.component(
                .weekday,
                from: date
            )
        let dayIndex =
            ((weekday + 5) % 7) +
            1

        return plan.weeks[
            weekIndex
        ]
        .days
        .first(
            where: {
                $0.dayIndex ==
                    dayIndex
            }
        )?
        .sessions ?? []
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

private struct HomeWeeklyProgressDaySheet:
    View {
    let selection:
        HomeWeeklyProgressDaySelection

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    if selection.planned.isEmpty &&
                        selection.actual.isEmpty {
                        ContentUnavailableView(
                            ATHLTHLocalization.choose(
                                english:
                                    "No workouts",
                                norwegian:
                                    "Ingen økter"
                            ),
                            systemImage:
                                "calendar"
                        )
                        .padding(.top, 40)
                    }

                    if !selection
                        .planned
                        .isEmpty {
                        sectionTitle(
                            ATHLTHLocalization.choose(
                                english:
                                    "Planned",
                                norwegian:
                                    "Planlagt"
                            )
                        )

                        ForEach(
                            selection.planned
                        ) { workout in
                            plannedRow(
                                workout
                            )
                        }
                    }

                    if !selection
                        .actual
                        .isEmpty {
                        sectionTitle(
                            ATHLTHLocalization.choose(
                                english:
                                    "Completed workouts",
                                norwegian:
                                    "Utførte økter"
                            )
                        )

                        ForEach(
                            selection.actual
                        ) { workout in
                            actualRow(
                                workout
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(
                Color(
                    .systemGroupedBackground
                )
                .ignoresSafeArea()
            )
            .navigationTitle(
                selection.date.formatted(
                    .dateTime
                        .weekday(.wide)
                        .day()
                        .month(.wide)
                )
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
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

    private func plannedRow(
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

    private func actualRow(
        _ workout: WorkoutSummary
    ) -> some View {
        HStack(spacing: 11) {
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
                ATHLTHTheme.accentDeep
            )
            .frame(
                width: 36,
                height: 36
            )
            .background(
                ATHLTHTheme.accentSoft,
                in: Circle()
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    workout.activity
                        .rawValue
                )
                .font(
                    .subheadline
                        .weight(.semibold)
                )

                Text(
                    actualDetail(
                        workout
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    ATHLTHTheme.mutedText
                )
            }

            Spacer()
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

    private func plannedDetail(
        _ workout: PlannedSession
    ) -> String {
        var parts: [String] = []

        if let start =
                workout.scheduledStart {
            parts.append(
                start.formatted(
                    date: .omitted,
                    time: .shortened
                )
            )
        }

        if let minutes =
                workout.durationMinutes {
            parts.append(
                "\(minutes) min"
            )
        }

        if let distance =
                workout
                    .targetDistanceKilometers {
            parts.append(
                String(
                    format:
                        "%.1f km",
                    distance
                )
            )
        }

        if !workout.exercises
            .isEmpty {
            parts.append(
                ATHLTHLocalization.format(
                    english:
                        "%d exercises",
                    norwegian:
                        "%d øvelser",
                    workout.exercises.count
                )
            )
        }

        return parts.isEmpty
            ? workout.kind.title
            : parts.joined(
                separator: " · "
            )
    }

    private func actualDetail(
        _ workout: WorkoutSummary
    ) -> String {
        let minutes =
            max(
                Int(
                    (workout.duration / 60)
                        .rounded()
                ),
                0
            )
        var parts =
            [
                "\(minutes) min"
            ]

        if let distance =
                workout.distanceMeters,
           distance > 0 {
            parts.append(
                String(
                    format:
                        "%.1f km",
                    distance / 1_000
                )
            )
        }

        return parts.joined(
            separator: " · "
        )
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
