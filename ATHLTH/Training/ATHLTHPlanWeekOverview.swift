import SwiftUI

/// Stable seven-day Plan presentation. Navigation state and completion
/// evidence remain owned by the active Train Plan workspace.
struct ATHLTHPlanWeekOverview: View {
    let week: TrainingPlanWeek
    let plan: TrainingPlan
    let weekday: (Int) -> String
    let planDayDate: (Int) -> Date
    let isCompleted: (PlannedSession) -> Bool
    let onSelectDay: (UUID) -> Void

    private let graphite = ATHLTHTrainDesign.ink
    private let secondaryInk = ATHLTHTrainDesign.secondary
    private let warmGold = ATHLTHTrainDesign.bronze
    private let soft = ATHLTHTrainDesign.paleGold.opacity(0.25)

    private func localized(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private func workoutSubtitle(_ workout: PlannedSession) -> String {
        guard let minutes = workout.durationMinutes else { return workout.kind.title }
        return workout.kind.title + " · " + String(minutes) + " min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(localized("Week overview", "Ukeoversikt"))
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(graphite)
                Spacer()
                Text(plan.builderProfile?.mode == .advanced
                     ? localized("Advanced plan", "Avansert plan")
                     : localized("Simple plan", "Enkel plan"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryInk)
            }

            ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                let workouts = day.sessions.filter { !$0.isExplicitRestDay }
                Button {
                    onSelectDay(day.id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 3) {
                            Text(weekday(day.dayIndex))
                                .font(.caption2.weight(.semibold))
                            Text(planDayDate(day.dayIndex)
                                .formatted(.dateTime.day()))
                                .font(.system(size: 20, weight: .semibold, design: .serif))
                        }
                        .foregroundStyle(graphite)
                        .frame(width: 43)

                        VStack(alignment: .leading, spacing: 7) {
                            if workouts.isEmpty {
                                Label(
                                    day.sessions.contains(where: \.isExplicitRestDay)
                                        ? localized("Rest and recovery", "Hvile og restitusjon")
                                        : localized("No workout planned", "Ingen økt planlagt"),
                                    systemImage: "leaf"
                                )
                                .font(.subheadline)
                                .foregroundStyle(secondaryInk)
                            } else {
                                ForEach(workouts) { workout in
                                    HStack(spacing: 7) {
                                        Image(systemName: workout.kind.systemImage)
                                            .foregroundStyle(warmGold)
                                            .frame(width: 18)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(workout.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(graphite)
                                                .lineLimit(2)
                                            Text(workoutSubtitle(workout))
                                                .font(.caption2)
                                                .foregroundStyle(secondaryInk)
                                        }
                                        Spacer(minLength: 0)
                                        if isCompleted(workout) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(warmGold)
                                        }
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(soft.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
    }
}
