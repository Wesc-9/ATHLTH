import SwiftUI

struct HomeThisWeekCard: View {
    let plan: TrainingPlan?
    let workouts: [WorkoutSummary]
    let streakCount: Int
    let onOpenProgress: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        ATHLTHCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("This Week")
                        .font(.title3.weight(.bold))
                    Text(weekSummary)
                        .font(.caption)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                }

                Spacer()

                Button("Progress") {
                    onOpenProgress()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHTheme.accentDeep)
                .buttonStyle(.plain)
            }

            HStack(spacing: 7) {
                ForEach(weekDates, id: \.self) { date in
                    dayCell(date)
                }
            }
            .padding(.top, 14)

            HStack(spacing: 10) {
                summaryPill(
                    value: "\(completedWorkoutCount)",
                    title: plannedWorkoutCount > 0
                        ? "of \(plannedWorkoutCount) workouts"
                        : "workouts",
                    icon: "checkmark.circle.fill",
                    tint: ATHLTHTheme.vitality
                )

                if runningDistanceKilometers > 0 {
                    summaryPill(
                        value: String(
                            format: "%.1f km",
                            runningDistanceKilometers
                        ),
                        title: "distance",
                        icon: "figure.run",
                        tint: .green
                    )
                }

                if streakCount > 0 {
                    summaryPill(
                        value: "\(streakCount)",
                        title: "day streak",
                        icon: "flame.fill",
                        tint: .orange
                    )
                }
            }
            .padding(.top, 13)
        }
    }

    private var weekInterval: DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: Date()) ??
            DateInterval(
                start: calendar.startOfDay(for: Date()),
                duration: 7 * 86_400
            )
    }

    private var weekDates: [Date] {
        let start = weekInterval.start
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private var plannedSessions: [PlannedSession] {
        guard let plan else { return [] }

        return plan.weeks
            .flatMap(\.days)
            .flatMap(\.sessions)
            .filter {
                guard let start = $0.scheduledStart else { return false }
                return weekInterval.contains(start)
            }
    }

    private var completedWorkouts: [WorkoutSummary] {
        workouts.filter { weekInterval.contains($0.startDate) }
    }

    private var completedWorkoutCount: Int {
        completedWorkouts.count
    }

    private var plannedWorkoutCount: Int {
        plannedSessions.count
    }

    private var runningDistanceKilometers: Double {
        completedWorkouts
            .filter { $0.activity == .running }
            .compactMap(\.distanceMeters)
            .reduce(0, +) / 1_000
    }

    private var weekSummary: String {
        if plannedWorkoutCount > 0 {
            return "\(completedWorkoutCount) completed · \(plannedWorkoutCount) planned"
        }

        if completedWorkoutCount > 0 {
            return "\(completedWorkoutCount) workout\(completedWorkoutCount == 1 ? "" : "s") completed"
        }

        return "Your completed training will build the week here."
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let actual = completedWorkouts.filter {
            calendar.isDate($0.startDate, inSameDayAs: date)
        }
        let planned = plannedSessions.filter {
            guard let start = $0.scheduledStart else { return false }
            return calendar.isDate(start, inSameDayAs: date)
        }
        let isToday = calendar.isDateInToday(date)
        let hasActual = !actual.isEmpty

        VStack(spacing: 7) {
            Text(date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(isToday ? .bold : .semibold))
                .foregroundStyle(
                    isToday
                        ? ATHLTHTheme.primaryText
                        : ATHLTHTheme.mutedText
                )

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        hasActual
                            ? ATHLTHTheme.vitalitySoft
                            : isToday
                                ? ATHLTHTheme.champagneSoft
                                : Color.primary.opacity(0.025)
                    )

                if let workout = actual.first {
                    Image(systemName: workout.activity.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.vitality)
                } else if let session = planned.first {
                    Image(systemName: session.kind.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ATHLTHTheme.mutedText)
                } else {
                    Circle()
                        .fill(
                            isToday
                                ? ATHLTHTheme.premiumGold.opacity(0.55)
                                : Color.primary.opacity(0.10)
                        )
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 40)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            ATHLTHTheme.premiumGold.opacity(0.50),
                            lineWidth: 1
                        )
                }
            }

            if hasActual {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ATHLTHTheme.vitality)
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryPill(
        value: String,
        title: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(ATHLTHTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            tint.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

struct HomeGettingStartedCard: View {
    let healthConnected: Bool
    let hasPlan: Bool
    let hasGoal: Bool

    var body: some View {
        ATHLTHCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make ATHLTH Yours")
                    .font(.title3.weight(.bold))
                Text("Finish the essentials and Home will adapt around your training.")
                    .font(.caption)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            VStack(spacing: 9) {
                setupRow(
                    title: "Connect Apple Health",
                    complete: healthConnected,
                    destination: AnyView(ATHLTHSettingsView())
                )

                setupRow(
                    title: "Create a training plan",
                    complete: hasPlan,
                    destination: AnyView(
                        AdvancedPlannerView(onOpenPrograms: {})
                    )
                )

                setupRow(
                    title: "Set your first goal",
                    complete: hasGoal,
                    destination: AnyView(GoalsHubView())
                )
            }
            .padding(.top, 12)
        }
    }

    private func setupRow(
        title: String,
        complete: Bool,
        destination: AnyView
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 11) {
                Image(
                    systemName:
                        complete
                            ? "checkmark.circle.fill"
                            : "circle"
                )
                .foregroundStyle(
                    complete
                        ? ATHLTHTheme.vitality
                        : ATHLTHTheme.mutedText
                )

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)

                Spacer()

                if !complete {
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                Color.primary.opacity(0.028),
                in: RoundedRectangle(cornerRadius: 13)
            )
        }
        .buttonStyle(.plain)
        .disabled(complete)
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
