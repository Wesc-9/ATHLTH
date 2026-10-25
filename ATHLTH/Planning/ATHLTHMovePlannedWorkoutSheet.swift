import SwiftUI

/// Move a planned session only after an explicit confirmation. The target
/// day can already contain sessions; this flow never replaces any of them.
struct ATHLTHMovePlannedWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let plan: TrainingPlan
    let workout: PlannedSession

    @State private var targetDay: Date
    @State private var moveFailed = false

    init(plan: TrainingPlan, workout: PlannedSession) {
        self.plan = plan
        self.workout = workout

        let occurrence = TrainingPlanSchedule.occurrences(in: plan)
            .first { $0.session.id == workout.id }
        let firstDay = Calendar.current.startOfDay(
            for: plan.startDate ?? Date()
        )
        _targetDay = State(initialValue: Calendar.current.startOfDay(
            for: occurrence?.date ?? firstDay
        ))
    }

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: plan.startDate ?? Date())
        let lastDay = calendar.date(
            byAdding: .day,
            value: max(plan.weeks.count * 7 - 1, 0),
            to: firstDay
        ) ?? firstDay
        return firstDay...lastDay
    }

    private var sourceDay: Date? {
        TrainingPlanSchedule.occurrences(in: plan)
            .first { $0.session.id == workout.id }
            .map { Calendar.current.startOfDay(for: $0.date) }
    }

    private var isNewDay: Bool {
        guard let sourceDay else { return false }
        return !Calendar.current.isDate(sourceDay, inSameDayAs: targetDay)
    }

    private var plannedAtDestination: [PlannedSession] {
        TrainingPlanSchedule.sessions(in: plan, on: targetDay)
            .filter { $0.id != workout.id }
    }

    private var isRestDestination: Bool {
        guard let currentPlan = session.trainingPlan(withID: plan.id)
        else { return false }
        return TrainingPlanSchedule.isRestDay(
            in: currentPlan, on: targetDay
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ATHLTHLocalization.choose(
                            english: "MOVE WORKOUT",
                            norwegian: "FLYTT ØKT"
                        ))
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        Text(workout.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        if let sourceDay {
                            Text(ATHLTHLocalization.choose(
                                english: "Currently \(sourceDay.formatted(date: .abbreviated, time: .omitted))",
                                norwegian: "Nå \(sourceDay.formatted(date: .abbreviated, time: .omitted))"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker(
                            ATHLTHLocalization.choose(
                                english: "New day",
                                norwegian: "Ny dag"
                            ),
                            selection: $targetDay,
                            in: dateRange,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(ATHLTHTheme.accentDeep)

                        if isRestDestination {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "This date is a planned rest day. Remove the rest day in Plan before moving a workout here.",
                                    norwegian: "Denne datoen er en hviledag. Fjern hviledagen i Plan før du flytter en økt hit."
                                ),
                                systemImage: "leaf"
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                        } else if plannedAtDestination.isEmpty {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "No other workouts planned on this day.",
                                    norwegian: "Ingen andre økter planlagt denne dagen."
                                ),
                                systemImage: "calendar"
                            )
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.mutedText)
                        } else {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Already scheduled for this day",
                                    norwegian: "Allerede planlagt denne dagen"
                                ))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ATHLTHTheme.accentDeep)

                                ForEach(plannedAtDestination) { other in
                                    Label(other.title, systemImage: other.kind.systemImage)
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHTheme.primaryText)
                                }

                                Text(ATHLTHLocalization.choose(
                                    english: "These sessions remain unchanged.",
                                    norwegian: "Disse øktene blir ikke endret."
                                ))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHTheme.mutedText)
                            }
                        }
                    }
                    .padding(15)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: 22)
                    )

                    if moveFailed {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Could not move the workout. The plan has not been changed.",
                                norwegian: "Kunne ikke flytte økten. Treningsplanen er uendret."
                            ),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }

                    Button {
                        guard isNewDay,
                              !isRestDestination,
                              session.activePlan?.id == plan.id,
                              session.movePlanSession(
                                planID: plan.id,
                                sessionID: workout.id,
                                to: targetDay
                              )
                        else {
                            moveFailed = true
                            return
                        }
                        dismiss()
                    } label: {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Confirm move",
                                norwegian: "Bekreft flytting"
                            ),
                            systemImage: "calendar.badge.clock"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        ATHLTHTheme.accentDeep,
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                    .disabled(!isNewDay || isRestDestination)
                }
                .padding(17)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Move workout",
                norwegian: "Flytt økt"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel",
                        norwegian: "Avbryt"
                    )) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
