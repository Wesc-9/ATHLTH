import Foundation

/// Resolves plan days from the plan's start date, not the current weekday.
/// dayIndex 1 is the first day of the plan (which need not be a Monday).
enum ATHLTHTrainingPlanSchedule {
    static func sessions(
        in plan: TrainingPlan,
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlannedSession] {
        guard !plan.weeks.isEmpty else { return [] }

        guard let startDate = plan.startDate else {
            // Preserve historical plans that were saved without a start date.
            let weekday = calendar.component(.weekday, from: date)
            let mondayBasedIndex = ((weekday + 5) % 7) + 1
            return plan.weeks.first?.days
                .first(where: { $0.dayIndex == mondayBasedIndex })?.sessions ?? []
        }

        let first = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: date)
        guard let dayOffset = calendar.dateComponents([.day], from: first, to: target).day,
              dayOffset >= 0,
              dayOffset < plan.weeks.count * 7 else {
            return []
        }

        let weekIndex = dayOffset / 7
        let dayIndex = (dayOffset % 7) + 1
        return plan.weeks[weekIndex].days
            .first(where: { $0.dayIndex == dayIndex })?.sessions ?? []
    }
}
