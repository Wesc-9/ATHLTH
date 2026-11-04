import SwiftUI

/// A read-only overview of the one canonical TrainingPlan in AppSessionStore.
/// Selection and copying delegate to the existing plan editor and storage
/// engine; this view does not maintain a second plan or workout model.
struct ATHLTHStudioPlanOverviewView: View {
    enum Display {
        case overview
        case progress
    }

    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let plan: TrainingPlan
    let display: Display
    let selectedWeekID: UUID?
    let onSelect: (UUID, UUID?) -> Void
    let onCopyWeek: (UUID) -> Void

    private var weeks: [TrainingPlanWeek] { plan.weeks }

    private var scheduledWorkouts: Int {
        weeks.reduce(0) {
            $0 + ATHLTHStudioPlanWeekSummary.calculate($1).workouts
        }
    }

    private var plannedMinutes: Int {
        weeks.reduce(0) {
            $0 + ATHLTHStudioPlanWeekSummary.calculate($1).knownMinutes
        }
    }

    private var missingDurationCount: Int {
        weeks.reduce(0) {
            $0 + ATHLTHStudioPlanWeekSummary.calculate($1).missingDurationCount
        }
    }

    private var completedWorkouts: Int {
        weeks.reduce(0) { count, week in
            count + week.days.flatMap(\.sessions).filter {
                !$0.isExplicitRestDay &&
                session.isPlanSessionCompleted(
                    planID: plan.id, sessionID: $0.id,
                    healthWorkouts: health.workouts,
                    strengthHistory: strength.workoutHistory
                )
            }.count
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let numberOfColumns = geometry.size.width >= 1350 ? 3 :
                geometry.size.width >= 760 ? 2 : 1
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 13, alignment: .top),
                count: numberOfColumns
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryHeader
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 13) {
                        ForEach(weeks) { week in
                            weekCard(week)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.automatic)
        }
        .accessibilityIdentifier("athlth-studio-whole-plan-overview")
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(display == .progress
                        ? ATHLTHLocalization.choose(
                            english: "PLAN PROGRESS", norwegian: "PLANFREMDRIFT"
                        )
                        : ATHLTHLocalization.choose(
                            english: "COMPLETE PLAN", norwegian: "HELE PLANEN"
                        )
                    )
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(ATHLTHStudioStyle.gold)

                    Text(display == .progress
                        ? ATHLTHLocalization.choose(
                            english: "Planned versus completed",
                            norwegian: "Planlagt mot gjennomført"
                        )
                        : ATHLTHLocalization.choose(
                            english: "All weeks and every training day",
                            norwegian: "Alle ukene og hver treningsdag"
                        )
                    )
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                statistic(
                    name: ATHLTHLocalization.choose(
                        english: "Weeks", norwegian: "Uker"
                    ),
                    value: "\(weeks.count)"
                )
                statistic(
                    name: ATHLTHLocalization.choose(
                        english: "Planned workouts", norwegian: "Planlagte økter"
                    ),
                    value: "\(scheduledWorkouts)"
                )
                statistic(
                    name: ATHLTHLocalization.choose(
                        english: "Completed", norwegian: "Gjennomført"
                    ),
                    value: "\(completedWorkouts)"
                )
                statistic(
                    name: ATHLTHLocalization.choose(
                        english: "Known hours", norwegian: "Kjente timer"
                    ),
                    value: String(format: "%.1f", Double(plannedMinutes) / 60)
                )
            }
            if missingDurationCount > 0 {
                Label(
                    ATHLTHLocalization.format(
                        english: "%d workouts have no duration; totals are incomplete.",
                        norwegian: "%d økter mangler varighet. Summen er ikke fullstendig.",
                        missingDurationCount
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(ATHLTHStudioStyle.outline.opacity(0.5))
        }
    }

    private func statistic(name: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ATHLTHStudioStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekCard(_ week: TrainingPlanWeek) -> some View {
        let planned = ATHLTHStudioPlanWeekSummary.calculate(week)
        let workouts = week.days.flatMap(\.sessions).filter { !$0.isExplicitRestDay }
        let completed = workouts.filter { workout in
            session.isPlanSessionCompleted(
                planID: plan.id, sessionID: workout.id,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        }.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    onSelect(week.id, nil)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ATHLTHLocalization.format(
                            english: "Week %d", norwegian: "Uke %d",
                            week.weekNumber
                        ))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                        Text(ATHLTHLocalization.format(
                            english: "%d workouts · %d planned min",
                            norwegian: "%d økter · %d planlagte min",
                            planned.workouts, planned.knownMinutes
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 6)

                Menu {
                    Button {
                        onCopyWeek(week.id)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Copy entire week", norwegian: "Kopier hele uken"
                        ), systemImage: "square.on.square")
                    }
                    .disabled(workouts.isEmpty &&
                              !week.days.contains(where: {
                                  $0.sessions.contains(where: \.isExplicitRestDay)
                              }))
                    Button {
                        onSelect(week.id, nil)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Open week", norwegian: "Åpne uken"
                        ), systemImage: "calendar")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel(ATHLTHLocalization.choose(
                    english: "Week actions", norwegian: "Ukehandlinger"
                ))
            }

            ProgressView(value: workouts.isEmpty ? 0 :
                Double(completed) / Double(workouts.count))
                .tint(ATHLTHStudioStyle.gold)
            Text(ATHLTHLocalization.format(
                english: "%d of %d completed",
                norwegian: "%d av %d gjennomført",
                completed, workouts.count
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)

            Divider()

            ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                dayButton(day, in: week)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(
                    selectedWeekID == week.id
                        ? ATHLTHStudioStyle.gold.opacity(0.75)
                        : ATHLTHStudioStyle.outline.opacity(0.5),
                    lineWidth: selectedWeekID == week.id ? 1.5 : 1
                )
        }
    }

    private func dayButton(
        _ day: TrainingPlanDay,
        in week: TrainingPlanWeek
    ) -> some View {
        let weekIndex = weeks.firstIndex(where: { $0.id == week.id }) ?? 0
        let date = ATHLTHStudioPlanWeekSummary.date(
            for: day, inWeekIndex: weekIndex, planStart: plan.startDate
        )
        let training = day.sessions.filter { !$0.isExplicitRestDay }
        let isRestDay = day.sessions.contains(where: \.isExplicitRestDay)
        let completed = training.filter {
            session.isPlanSessionCompleted(
                planID: plan.id, sessionID: $0.id,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            )
        }.count
        let skipped = training.filter {
            session.isPlanSessionSkipped(planID: plan.id, sessionID: $0.id)
        }.count

        return Button {
            onSelect(week.id, day.id)
        } label: {
            HStack(spacing: 10) {
                Text(date?.formatted(.dateTime.weekday(.abbreviated))
                     ?? "\(day.dayIndex)")
                    .font(.caption.weight(.semibold))
                    .frame(width: 36, alignment: .leading)
                    .foregroundStyle(ATHLTHStudioStyle.gold)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isRestDay
                        ? ATHLTHLocalization.choose(
                            english: "Rest day", norwegian: "Hviledag"
                        )
                        : training.isEmpty
                            ? ATHLTHLocalization.choose(
                                english: "Not planned", norwegian: "Ikke planlagt"
                            )
                            : training.map(\.title).joined(separator: " · ")
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ATHLTHStudioStyle.ink)
                    .lineLimit(1)

                    if !training.isEmpty {
                        Text(ATHLTHLocalization.format(
                            english: "%d workout(s) · %d completed · %d skipped",
                            norwegian: "%d økt(er) · %d gjennomført · %d hoppet over",
                            training.count, completed, skipped
                        ))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: !training.isEmpty && completed == training.count
                      ? "checkmark.circle.fill"
                      : skipped > 0 ? "minus.circle"
                      : isRestDay ? "moon.zzz"
                      : training.isEmpty ? "plus.circle" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(
                        !training.isEmpty && completed == training.count
                            ? ATHLTHStudioStyle.gold : .secondary
                    )
            }
            .padding(.vertical, display == .progress ? 8 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
