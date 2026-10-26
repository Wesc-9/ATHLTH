import SwiftUI

/// Read-only, independently diffable week/day outline for Train → Plan.
/// Editing and selection state remain in the owning Plan workspace.
struct ATHLTHTrainPlanAllWeeksView: View {
    let plan: TrainingPlan
    let onSelectDay: (Int, UUID) -> Void

    private var ink: Color { ATHLTHTrainDesign.ink }
    private var secondary: Color { ATHLTHTrainDesign.secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ATHLTHLocalization.choose(
                english: "Entire training plan", norwegian: "Hele treningsplanen"
            ))
            .font(.system(size: 20, weight: .regular, design: .serif))
            .accessibilityAddTraits(.isHeader)

            ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { index, week in
                weekSection(week, at: index)
            }
        }
    }

    private func weekSection(
        _ week: TrainingPlanWeek, at weekIndex: Int
    ) -> some View {
        DisclosureGroup {
            LazyVStack(spacing: 4) {
                ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                    Button {
                        onSelectDay(weekIndex, day.id)
                    } label: {
                        HStack(spacing: 11) {
                            Text(dayDate(day.dayIndex, week: weekIndex)
                                .formatted(.dateTime.weekday(.abbreviated).day()))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(secondary)
                                .frame(width: 50, alignment: .leading)

                            VStack(alignment: .leading, spacing: 3) {
                                if day.sessions.isEmpty {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Rest day", norwegian: "Hviledag"
                                    ))
                                    .font(.subheadline)
                                } else {
                                    ForEach(day.sessions) { workout in
                                        Text(workout.title)
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ink)
                }
            }
            .padding(.top, 7)
        } label: {
            let workoutCount = week.days.flatMap(\.sessions)
                .filter { !$0.isExplicitRestDay }.count
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Week \(weekIndex + 1)", norwegian: "Uke \(weekIndex + 1)"
                ))
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "\(workoutCount) workouts", norwegian: "\(workoutCount) økter"
                ))
                .font(.caption)
                .foregroundStyle(secondary)
                .padding(.trailing, 7)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
    }

    private func dayDate(_ dayIndex: Int, week: Int) -> Date {
        let start = Calendar.current.startOfDay(for: plan.startDate ?? .now)
        return Calendar.current.date(
            byAdding: .day, value: week * 7 + dayIndex - 1, to: start
        ) ?? start
    }
}
