import SwiftUI

/// Reusable plan workout index, isolated from Plan's complex sheets and
/// editing state. It receives navigation and completion evidence as inputs.
struct ATHLTHPlanWorkoutLibrary: View {
    let plan: TrainingPlan
    let weekday: (Int) -> String
    let isCompleted: (PlannedSession) -> Bool
    let onSelectWorkout: (Int, UUID, UUID) -> Void

    private let graphite = ATHLTHTrainDesign.ink
    private let secondaryInk = ATHLTHTrainDesign.secondary
    private let warmGold = ATHLTHTrainDesign.bronze

    private var totalWorkoutCount: Int {
        plan.weeks.reduce(0) { count, week in
            count + week.days.reduce(0) { total, day in
                total + day.sessions.filter { !$0.isExplicitRestDay }.count
            }
        }
    }

    private func localized(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    private func subtitle(_ workout: PlannedSession) -> String {
        guard let minutes = workout.durationMinutes else { return workout.kind.title }
        return workout.kind.title + " · " + String(minutes) + " min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(localized("All workouts", "Alle økter"))
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(graphite)
                Spacer()
                Text(String(totalWorkoutCount) + " " + localized("workouts", "økter"))
                    .font(.caption)
                    .foregroundStyle(secondaryInk)
            }
            ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { item in
                let entries = item.element.days
                    .sorted(by: { $0.dayIndex < $1.dayIndex })
                    .flatMap { day in
                        day.sessions.filter { !$0.isExplicitRestDay }
                            .map { (day: day, workout: $0) }
                    }
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(localized("Week", "Uke") + " " + String(item.offset + 1))
                                .font(.system(.headline, design: .serif, weight: .semibold))
                                .foregroundStyle(graphite)
                            Spacer()
                            Text(String(entries.count) + " " + localized("workouts", "økter"))
                                .font(.caption2)
                                .foregroundStyle(secondaryInk)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)

                        ForEach(entries, id: \.workout.id) { entry in
                            Button {
                                onSelectWorkout(item.offset, entry.day.id, entry.workout.id)
                            } label: {
                                HStack(spacing: 11) {
                                    Text(weekday(entry.day.dayIndex))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(secondaryInk)
                                        .frame(minWidth: 31, alignment: .leading)
                                    Image(systemName: entry.workout.kind.systemImage)
                                        .font(.body)
                                        .foregroundStyle(warmGold)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.workout.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(graphite)
                                        Text(subtitle(entry.workout))
                                            .font(.caption2)
                                            .foregroundStyle(secondaryInk)
                                    }
                                    Spacer(minLength: 0)
                                    if isCompleted(entry.workout) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(warmGold)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(secondaryInk)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(localized("Open workout details", "Åpne øktdetaljer"))
                            if entry.workout.id != entries.last?.workout.id {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }
}
